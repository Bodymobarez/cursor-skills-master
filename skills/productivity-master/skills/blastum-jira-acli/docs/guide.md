# Jira ACLI Guide

## Installation

### ACLI (Atlassian CLI)

```bash
brew tap atlassian/homebrew-acli && brew install acli
```

**Auth**: Run `acli jira auth login` before using Jira commands. Each ACLI version is supported for 6 months; update regularly.

### md-to-adf

```bash
brew tap imzak31/md-to-adf && brew install md-to-adf
```

**Usage**: `md-to-adf convert <file.md>` outputs ADF JSON to stdout. To save to file:

```bash
md-to-adf convert doc.md > doc.adf.json
```

---

## Markdown to ADF

Jira v3 REST requires descriptions and comments in Atlassian Document Format (ADF), not plain text. Use md-to-adf locally (no data leaves your machine).

**When to convert**: Descriptions, comments.

**Flow**:

```bash
echo "# Title\n\nBody" > tmp.md
md-to-adf convert tmp.md > tmp.adf.json
```

ACLI accepts ADF via `--description-file` (create/edit) and `--body-file` (comment).

---

## Create

```bash
acli jira workitem create --summary "Task title" --project PROJ --type Task
```

**Options**: `--description`, `--description-file`, `--from-json`, `--assignee`, `--label`, `--parent`

**With markdown description**:

```bash
md-to-adf convert desc.md > desc.adf.json
acli jira workitem create --summary "Task" --project PROJ --type Task --description-file desc.adf.json
```

---

## Read

```bash
acli jira workitem view KEY-123
```

**Options**: `--fields "summary,comment"`, `--json`, `--web`

---

## Update

```bash
acli jira workitem edit --key KEY-1 --summary "New summary" --assignee "user@example.com"
```

**Options**: `--jql`, `--filter`, `--from-json`, `--description-file`, `--yes`

**With markdown description**: Convert md→ADF first, then use `--description-file desc.adf.json`.

---

## Delete

```bash
acli jira workitem delete --key "KEY-1,KEY-2" --yes
```

**Options**: `--jql`, `--filter`, `--from-file`, `--yes` (required for non-interactive)

---

## Search

```bash
acli jira workitem search --jql "project = PROJ" --fields "key,summary,status" --limit 50 --json
```

**Options**: `--jql`, `--filter`, `--fields`, `--limit`, `--paginate`, `--json`, `--csv`

---

## Comment

```bash
acli jira workitem comment create --key KEY-1 --body "Plain text comment"
```

**With markdown body**:

```bash
md-to-adf convert comment.md > comment.adf.json
acli jira workitem comment create --key KEY-1 --body-file comment.adf.json
```

**Options**: `--jql`, `--filter`, `--body`, `--body-file`, `--editor`

---

## Transition

```bash
acli jira workitem transition --key KEY-1 --status "Done" --yes
```

**Options**: `--jql`, `--filter`, `--status`, `--yes`

---

## Quick Reference

| Operation | Command | Key flags |
|-----------|---------|-----------|
| Create | `acli jira workitem create` | `--summary`, `--project`, `--type`, `--description-file` |
| Read | `acli jira workitem view KEY` | `--fields`, `--json`, `--web` |
| Update | `acli jira workitem edit` | `--key`, `--summary`, `--description-file`, `--yes` |
| Delete | `acli jira workitem delete` | `--key`, `--jql`, `--yes` |
| Search | `acli jira workitem search` | `--jql`, `--fields`, `--limit`, `--json` |
| Comment | `acli jira workitem comment create` | `--key`, `--body`, `--body-file` |
| Transition | `acli jira workitem transition` | `--key`, `--status`, `--yes` |
