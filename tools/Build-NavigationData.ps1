[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SourceUrl = 'https://davidmegginson.github.io/ourairports-data/navaids.csv',

    [Parameter()]
    [ValidatePattern('^[A-Z]{2}$')]
    [string]$Country = 'DE',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$baseUrl = 'https://raw.githubusercontent.com/ckweb1/esp32-navigation-data/main/'
$supportedTypes = @('NDB', 'NDB-DME', 'VOR', 'VOR-DME', 'VORTAC')
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function ConvertTo-OptionalNumber {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter()]
        [switch]$Integer
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $number = [double]::Parse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture
    )
    if ($Integer) {
        return [int][Math]::Round($number)
    }
    return $number
}

function Get-TileName {
    param(
        [Parameter(Mandatory)]
        [double]$Latitude,

        [Parameter(Mandatory)]
        [double]$Longitude
    )

    $latitudeFloor = [Math]::Floor($Latitude)
    $longitudeFloor = [Math]::Floor($Longitude)
    $latitudePrefix = if ($latitudeFloor -ge 0) { 'N' } else { 'S' }
    $longitudePrefix = if ($longitudeFloor -ge 0) { 'E' } else { 'W' }

    return '{0}{1:D2}_{2}{3:D3}' -f @(
        $latitudePrefix,
        [Math]::Abs([int]$latitudeFloor),
        $longitudePrefix,
        [Math]::Abs([int]$longitudeFloor)
    )
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [int]$RecordCount
    )

    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $json = ($Value | ConvertTo-Json -Depth 12 -Compress) + "`n"
    [IO.File]::WriteAllText($Path, $json, $utf8NoBom)
    $bytes = [IO.File]::ReadAllBytes($Path)

    return [ordered]@{
        path    = $RelativePath.Replace('\', '/')
        sha256  = Get-Sha256Hex -Bytes $bytes
        size    = $bytes.Length
        records = $RecordCount
    }
}

$resolvedRoot = [IO.Path]::GetFullPath($Root)
$client = [Net.Http.HttpClient]::new()
$client.DefaultRequestHeaders.UserAgent.ParseAdd(
    'esp32-navigation-data-builder/1'
)
try {
    $sourceBytes = $client.GetByteArrayAsync($SourceUrl).GetAwaiter().GetResult()
}
finally {
    $client.Dispose()
}

$sourceSha = Get-Sha256Hex -Bytes $sourceBytes
$datasetVersion = 'oa-{0}' -f $sourceSha.Substring(0, 12)
$sourceText = $utf8NoBom.GetString($sourceBytes)
$records = @(
    $sourceText |
        ConvertFrom-Csv |
        Where-Object {
            $_.iso_country -eq $Country -and
            $_.type -in $supportedTypes
        } |
        ForEach-Object {
            $latitude = [double]::Parse(
                $_.latitude_deg,
                [Globalization.CultureInfo]::InvariantCulture
            )
            $longitude = [double]::Parse(
                $_.longitude_deg,
                [Globalization.CultureInfo]::InvariantCulture
            )
            if ($latitude -lt -90 -or $latitude -gt 90) {
                throw "Invalid latitude for $($_.ident): $latitude"
            }
            if ($longitude -lt -180 -or $longitude -gt 180) {
                throw "Invalid longitude for $($_.ident): $longitude"
            }

            [ordered]@{
                ident                = $_.ident.Trim()
                name                 = $_.name.Trim()
                type                 = $_.type.Trim()
                frequencyKhz         = [int][Math]::Round(
                    [double]::Parse(
                        $_.frequency_khz,
                        [Globalization.CultureInfo]::InvariantCulture
                    )
                )
                latitude             = [Math]::Round($latitude, 7)
                longitude            = [Math]::Round($longitude, 7)
                elevationFt          = ConvertTo-OptionalNumber -Value $_.elevation_ft -Integer
                slavedVariationDeg   = ConvertTo-OptionalNumber -Value $_.slaved_variation_deg
                magneticVariationDeg = ConvertTo-OptionalNumber -Value $_.magnetic_variation_deg
            }
        } |
        Sort-Object -Property ident, type, latitude, longitude
)

if ($records.Count -eq 0) {
    throw 'Source produced no supported records.'
}

$versionRoot = Join-Path $resolvedRoot 'v1'
if (Test-Path -LiteralPath $versionRoot) {
    Remove-Item -LiteralPath $versionRoot -Recurse -Force
}

$fullRelativePath = "v1/full/$Country.json"
$fullResult = Write-JsonFile `
    -Path (Join-Path $resolvedRoot $fullRelativePath) `
    -RelativePath $fullRelativePath `
    -RecordCount $records.Count `
    -Value ([ordered]@{
        schemaVersion = 1
        country       = $Country
        records       = $records
    })

$groups = [ordered]@{}
foreach ($record in $records) {
    $tile = Get-TileName `
        -Latitude $record.latitude `
        -Longitude $record.longitude
    if (-not $groups.Contains($tile)) {
        $groups[$tile] = [Collections.Generic.List[object]]::new()
    }
    $groups[$tile].Add($record)
}

$tiles = [ordered]@{}
foreach ($tile in ($groups.Keys | Sort-Object)) {
    $tileRecords = @($groups[$tile])
    $relativePath = "v1/tiles/$tile.json"
    $tiles[$tile] = Write-JsonFile `
        -Path (Join-Path $resolvedRoot $relativePath) `
        -RelativePath $relativePath `
        -RecordCount $tileRecords.Count `
        -Value ([ordered]@{
            schemaVersion = 1
            tile          = $tile
            records       = $tileRecords
        })
}

$manifestPath = Join-Path $resolvedRoot 'manifest.json'
$generatedAt = $null
if (Test-Path -LiteralPath $manifestPath) {
    try {
        $existingManifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json
        if ($existingManifest.datasetVersion -eq $datasetVersion) {
            $generatedAt = $existingManifest.generatedAt
        }
    }
    catch {
        Write-Warning 'Existing manifest is invalid and will be replaced.'
    }
}
if ([string]::IsNullOrWhiteSpace($generatedAt)) {
    $generatedAt = [DateTime]::UtcNow.ToString(
        'yyyy-MM-ddTHH:mm:ssZ',
        [Globalization.CultureInfo]::InvariantCulture
    )
}

$manifest = [ordered]@{
    schemaVersion   = 1
    datasetVersion  = $datasetVersion
    generatedAt     = $generatedAt
    source          = [ordered]@{
        name          = 'OurAirports navaids.csv'
        url           = $SourceUrl
        license       = 'Public Domain'
        sha256        = $sourceSha
        countryFilter = $Country
    }
    tileSizeDegrees = 1
    recordFormat    = 'json-v1'
    baseUrl         = $baseUrl
    full            = $fullResult
    tiles           = $tiles
}

$manifestJson = ($manifest | ConvertTo-Json -Depth 12 -Compress) + "`n"
[IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8NoBom)

Write-Host (
    'Built {0} records in {1} tiles as {2}.' -f
    $records.Count,
    $tiles.Count,
    $datasetVersion
)
