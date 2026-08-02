# GitHub CLI authentication compatibility

## Problem

The workflow preflight always passes `--active` to `gh auth status`. GitHub CLI
2.45.0 does not provide that flag, so a valid authenticated account is rejected
before any hosted operation can run.

## Design

Inspect `gh auth status --help` before checking authentication. Use `--active`
when the installed CLI advertises it and otherwise perform the same
hostname-scoped check without the flag. In both cases, retain the independent
`gh api user` lookup that validates the selected login.

## Verification

The shell fixture models CLIs with and without `--active`, plus authentication
failure and an empty active login. The existing Git and public-text checks must
continue to pass.
