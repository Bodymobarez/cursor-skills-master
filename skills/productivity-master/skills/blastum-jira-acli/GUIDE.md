---
name: blastum-jira-acli
description: Jira CRUD via ACLI and local md→ADF. Use when searching, creating, editing, or managing Jira issues without MCP. Triggers: jira, acli, create issue, search jira, edit jira, jql, transition, comment.
---
# Jira ACLI

Jira CRUD operations via Atlassian CLI (ACLI) and local markdown→ADF conversion. No MCP dependency.

## Install (prerequisites)

- **ACLI**: `brew tap atlassian/homebrew-acli && brew install acli`
- **md-to-adf**: `brew tap imzak31/md-to-adf && brew install md-to-adf`

## Resources

- [Guide](docs/guide.md)
- [Smoke test](examples/smoke-test.md)
