---
name: git-human-workflow
description: Manage Git repositories and GitHub from the terminal while preserving a configured human identity and removing prohibited automation markers from public Git or GitHub text. Use for branches, commits, tags, remotes, pushes, issues, pull requests, reviews, comments, releases, repository settings, or any GitHub CLI workflow.
---

# Git Human Workflow

## Overview

Use the bundled helper for every mutating Git or GitHub operation. It invokes only the local `git` and authenticated `gh` command-line clients; do not use browser, connector, MCP, or forge-specific skill tooling.

## Start Every Workflow

Run the preflight from the target repository:

```bash
bash "<skill-path>/scripts/git-human-workflow.sh" check
```

Install repository hooks once when direct commits may also be made outside the helper:

```bash
bash "<skill-path>/scripts/git-human-workflow.sh" install-repo-hooks
```

## Run Git Operations

Prefix the complete direct Git command with `git`:

```bash
bash "<skill-path>/scripts/git-human-workflow.sh" git switch -c feature/better-status
bash "<skill-path>/scripts/git-human-workflow.sh" git add README.md
bash "<skill-path>/scripts/git-human-workflow.sh" git commit -m "Clarify status output"
bash "<skill-path>/scripts/git-human-workflow.sh" git push -u origin feature/better-status
```

Use the helper for commits and amends even when hooks are installed. It resolves identity from repository config, global config, then the active GitHub CLI account, and it rejects conflicting author overrides.

## Run GitHub Operations

Prefix the complete GitHub CLI command with `gh`:

```bash
bash "<skill-path>/scripts/git-human-workflow.sh" gh issue create \
  --title "Clarify terminal workflow" \
  --body "Document the command-line path for this repository."

bash "<skill-path>/scripts/git-human-workflow.sh" gh pr create \
  --base main \
  --title "Clarify terminal workflow" \
  --body "Summarize the checked changes and validation."
```

Use explicit, inspectable text flags or files. Do not use browser/editor flows, generated fill text, or uninspectable remote templates for public content. For `gh api`, send checked JSON through `--input`; the helper also checks stdin payloads and content files.

## Public-Text Rule

Before publishing text, run it through `sanitize-text` when it may contain boilerplate:

```bash
printf '%s\n' "$draft" | \
  bash "<skill-path>/scripts/git-human-workflow.sh" sanitize-text
```

Review sanitized output before using it. The helper rejects remaining prohibited markers in branch names, messages, tags, notes, issues, pull requests, reviews, comments, releases, and API payloads. It intentionally does not scan source files or this plugin's documentation.

## Limits

Git branch references do not store an author. GitHub attributes hosted changes to the active `gh` account. The helper protects the commands it runs and installed commit hooks; it cannot stop a person from deliberately bypassing it with raw tools.
