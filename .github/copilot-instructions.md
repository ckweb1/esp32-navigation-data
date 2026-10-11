# Navigation Data Repository Guidelines

- Treat all output as unsupported educational data, never certified aviation data.
- Keep source attribution and licensing visible in `README.md` and `manifest.json`.
- Generate published files through `tools/Build-NavigationData.ps1`; do not hand-edit generated tiles.
- Keep generation deterministic for an unchanged source file.
- Preserve schema compatibility or increment `schemaVersion`.
- Validate coordinates, record counts, paths, and SHA-256 checksums before publication.
- Never add credentials, API keys, precise user positions, device identifiers, or private exports.
- Use English for schemas, code, logs, and canonical documentation.
