# Git Human Workflow

Git Human Workflow is an installable plugin for terminal-first Git and GitHub work. It wraps the local `git` and authenticated `gh` clients with identity checks and public-text guards.

## What it covers

- Git branches, commits, tags, notes, remotes, merges, rebases, fetches, pulls, and pushes
- GitHub issues, pull requests, reviews, comments, releases, repository administration, and `gh api`
- Commit identity resolved from repository configuration, global configuration, then the active GitHub CLI account
- Public Git and GitHub text checked before publication

## Use

Run the preflight in a repository:

```bash
bash skills/git-human-workflow/scripts/git-human-workflow.sh check
```

Use the helper as a prefix for direct terminal commands:

```bash
bash skills/git-human-workflow/scripts/git-human-workflow.sh git switch -c feature/terminal-workflow
bash skills/git-human-workflow/scripts/git-human-workflow.sh git commit -m "Add workflow guard"
bash skills/git-human-workflow/scripts/git-human-workflow.sh gh issue create \
  --title "Document terminal workflow" \
  --body "Add a concise usage example."
```

Install the repository hooks if commits may also be made with plain Git commands:

```bash
bash skills/git-human-workflow/scripts/git-human-workflow.sh install-repo-hooks
```

## Guard behavior

The helper rejects prohibited automation markers in public Git or GitHub text. It checks command arguments, message files, `gh api` input, and supported stdin payloads. It blocks browser/editor, generated-fill, and remote-template paths because their published text cannot be inspected first.

`sanitize-text` removes whole lines containing known boilerplate markers; review its output before publishing. Source files and the plugin documentation are intentionally outside this scan so the guard itself remains maintainable.

The GitHub side requires a logged-in `gh` account. It uses `github.com` unless `GH_HOST` names another host, and it supports CLI versions with and without `gh auth status --active`. GitHub records the active account as the actor for hosted changes; Git branch references themselves have no author field.

## Development

```bash
python3 /home/frank/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/git-human-workflow
python3 /home/frank/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .
bash tests/git-human-workflow-test.sh
```
