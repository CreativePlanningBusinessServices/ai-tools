### CLI Usage

**Serialize** &mdash; generate EDI output from a template and data:
```bash
editester serialize --template template.json --data data.json
editester serialize --template template.json --data data.json --format xml
editester serialize --template template.json --data data.json --today 2025-01-15T00:00:00.000Z --out output.txt
```

The data file has the shape `{ "data": [...], "documentNumber"?: number, "today"?: string }`.

**Deserialize** &mdash; process inbound data (CSV) through the parser/assembler/converter pipeline:
```bash
editester deserialize --template inbound.json --input data.csv
editester deserialize --template inbound.json --input data.csv --only-parse
editester deserialize --template inbound.json --input data.csv --only-assemble
editester deserialize --template inbound.json --input data.csv --out result.json
```

**Common flags:**
- `--no-validate` &mdash; skip AJV schema validation (useful for custom schemas not bundled in the binary)
- `--out <file>` &mdash; write output to a file instead of stdout
- `--help` / `--version` &mdash; show help or version info

Errors are written to stderr with exit code 1; successful output goes to stdout (or `--out`) with exit code 0.

### Offline / Network Behavior

The binary bundles all known JSON schemas at build time and works fully offline. If you need to validate against a schema not bundled, set the environment variable:
```bash
EDITESTER_ALLOW_NETWORK=1 editester serialize --template custom.json --data data.json
```