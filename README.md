# ESP32 Navigation Data

> [!CAUTION]
> Experimental and unsupported. These files are not certified aviation data and must not be used for primary or sole-source flight navigation.

Versioned regional VOR and NDB data for the educational ESP32-S3 navigation display.

## Published files

```text
manifest.json             Dataset metadata and SHA-256 checksums
v1/full/DE.json           Complete supported German navaid set
v1/tiles/N52_E007.json    One-degree regional tile example
schema/                   JSON schemas
```

The manifest is available at:

```text
https://raw.githubusercontent.com/ckweb1/esp32-navigation-data/main/manifest.json
```

## Update model

The device checks `manifest.json`, compares `datasetVersion` and tile checksums, then downloads only the current or changed geographic tiles. This is a tile-level delta update: unchanged tiles are not downloaded.

Downloads are written to a temporary file, validated, and activated only after a successful checksum and schema-version check. Cached files and embedded fallback records remain available offline.

## Source

Generated records are derived from the public-domain [OurAirports navaids dataset](https://ourairports.com/help/data-dictionary.html).

The initial build:

- keeps records whose `iso_country` is `DE`,
- includes `NDB`, `NDB-DME`, `VOR`, `VOR-DME`, and `VORTAC` types,
- creates compact JSON with descriptive, stable field names,
- partitions records into 1-degree latitude/longitude tiles.

## Build

```powershell
pwsh -File .\tools\Build-NavigationData.ps1
```

The generator uses PowerShell 7 and .NET without external modules.

## Licensing

Generator code is licensed under the MIT License. Generated navigation records remain derived from the public-domain OurAirports source. Review upstream terms before adding another source.
