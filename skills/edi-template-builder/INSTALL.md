# Installing the EDI Template Builder skill

## Contents

- 1. Install `jq` (one-time)
- 2. Install the skill
- 3. Upgrading from the zip install
- 4. Restart Claude Code
- 5. Try it
- Troubleshooting
- What's installed

This is a Claude Code skill. You do **not** need Node.js, Python, or any developer tools to use it — only `git`, `jq` (a small command-line utility) and `curl`. `curl` is usually already on macOS and Linux.

## 1. Install `jq` (one-time)

Check whether you already have it:
```sh
jq --version
```

If you get a version number, you're done with this step. Otherwise:

**macOS** (Homebrew — if you don't have brew, install it from https://brew.sh first):
```sh
brew install jq
```

**Debian / Ubuntu:**
```sh
sudo apt-get update && sudo apt-get install -y jq
```

**Windows** (Chocolatey):
```powershell
choco install jq
```

Or download the binary from https://jqlang.org/download/ and put it on your PATH.

## 2. Install the skill

The skill ships in the private `ai-tools` repo. **If you already have the skill from the old zip, do step 3 first.**

**macOS / Linux:**
```sh
git clone https://github.com/CreativePlanningBusinessServices/ai-tools.git
ai-tools/scripts/install-skills.sh
```

This symlinks every skill in the repo into `~/.claude/skills/`. To update later, run `git pull` in the clone — the link picks up changes automatically.

**Windows (PowerShell):** the installer relies on symlinks, so copy the folder instead, and copy it again after each `git pull`:
```powershell
git clone https://github.com/CreativePlanningBusinessServices/ai-tools.git
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\skills" | Out-Null
Copy-Item -Recurse -Force ai-tools\skills\edi-template-builder "$env:USERPROFILE\.claude\skills\"
```

Afterwards you should have `~/.claude/skills/edi-template-builder/SKILL.md` (or `%USERPROFILE%\.claude\skills\edi-template-builder\SKILL.md` on Windows).

## 3. Upgrading from the zip install

Earlier versions of this skill were distributed as a zip and registered a hook that anonymized benefit-feed JSON before Claude read it. The skill no longer anonymizes anything, and the hook has to be unregistered. Do these in order — the hook points at a script inside the old folder, so deleting the folder first leaves a hook that fails on every file read.

1. Unregister the hook (safe to re-run; it leaves every other hook alone):
   ```sh
   sh ai-tools/skills/edi-template-builder/scripts/remove-anonymize-hook.sh
   ```
2. Delete the old folder, or move it somewhere outside `~/.claude/skills/`:
   ```sh
   rm -rf ~/.claude/skills/edi-template-builder
   ```
3. Run the installer from step 2.

Any `*.anon.json` files left in your working folders came from the old version and can be deleted.

## 4. Restart Claude Code

Quit Claude Code completely and start it again. Skills and hooks are loaded when Claude Code starts, not while it's running.

## 5. Try it

In any Claude Code session, type:
```
/edi-template
```

Claude will ask which mode you want (build a new template or revise an existing one) and what inputs you have ready.

The first time you actually run a serialize step, the skill downloads the right `editester` binary for your platform (~70 MB) from Azure into the skill folder. This happens once and is silent thereafter.

## Troubleshooting

**`install-skills.sh` prints `skipped  edi-template-builder`** — a folder with that name is already in `~/.claude/skills/`, most likely the old zip install. Follow step 3.

**A hook error mentioning `anonymize-on-read.sh` on every file read** — the old hook is still registered but its script is gone. Run step 3.1 and restart Claude Code.

**`ensure-editester: download failed`** — your network can't reach `storageukgreadyedi.blob.core.windows.net`. Check the VPN / corporate proxy.

**Claude doesn't seem to know the skill exists** — confirm `SKILL.md` is at `~/.claude/skills/edi-template-builder/SKILL.md`, then fully quit and reopen Claude Code.

## What's installed

```
~/.claude/skills/edi-template-builder/   ← a link to ai-tools/skills/edi-template-builder
├── SKILL.md, INSTALL.md
├── commands/edi-template.md              ← the /edi-template slash command
├── scripts/                              ← cpbc-unique.sh, editester.sh, wrap-data.sh, ...
├── docs/                                 ← template-structure, handlebars helpers, editester CLI
├── templates/                            ← seed templates per carrier
└── bin/                                  ← populated on first editester run (gitignored)
```

Nothing is installed outside this folder.
