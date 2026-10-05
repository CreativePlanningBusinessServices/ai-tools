# Seed templates

Drop a finished, working template JSON into this folder to seed future runs of `/edi-template`. The skill globs `*.json` here and case-insensitively substring-matches filenames against the provider name supplied by the user.

## Naming

`<provider-slug>-<transaction-set>.json` — lowercase, hyphenated.

Examples:
- `principal-834.json`
- `aetna-834.json`
- `metlife-834.json`
- `principal-820.json`

The provider slug is what gets matched, so keep it consistent with how the team refers to the carrier ("Principal", "Principal Financial Group", and "PFG" should all map to a single `principal-*.json` file).

## What belongs here

- Finished templates that have been validated against real data and accepted by the carrier.
- Templates with `[TODO]` placeholders for sender/receiver IDs are fine — those values are per-installation, not per-provider.

## What does not belong here

- Work-in-progress templates. The skill assumes anything in this folder is a known-good starting point.
- Carrier-specific PII. Templates contain only field names and expressions, never data values, so this shouldn't come up.
