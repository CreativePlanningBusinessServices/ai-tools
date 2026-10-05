---
description: Build or revise an EDI benefits-feed template (X12 834, etc.) for an insurance carrier.
---

The user typed `/edi-template`. Open the [edi-template-builder skill](../SKILL.md) and run its workflow.

Arguments (if any) follow this slash command verbatim — they may include a provider name, a ClickUp task ID, file paths to a spec and/or sample data, an existing template path for a revision request, or a free-form description of vendor feedback. Use them to decide between the build flow and the revision flow as described in SKILL.md.

If the user typed `/edi-template` with no arguments, ask them in one short message which mode this is (build vs revise) and what inputs they have ready (provider name, ClickUp task ID, spec, sample data, existing template, feedback). Do not start working until you have what you need.
