---
name: blastum-github-cli
description: "GitHub CLI (gh) comprehensive reference for repositories, issues, pull requests, Actions, projects, releases, gists, codespaces, organizations, extensions, and all GitHub operations from the command line. Use for: (1) Repository management and cloning, (2) Issue and pull request workflows, (3) CI/CD pipeline management, (4) GitHub API automation, (5) Authentication and security setup, (6) Bulk operations and scripting. Triggers include requests for 'github', 'gh', 'git', 'repository', 'pull request', 'issue', 'ci/cd', 'workflow', 'release', 'clone', 'fork', 'merge', 'review', 'deploy', or GitHub-related development tasks."
metadata: {"moltbot":{"emoji":"🐙","requires":{"bins":["gh"]},"install":[{"id":"brew","kind":"brew","formula":"gh","bins":["gh"],"label":"Install GitHub CLI (brew)"},{"id":"apt","kind":"apt","package":"gh","bins":["gh"],"label":"Install GitHub CLI (apt)"}]}}
---

# GitHub CLI (gh)

Concise guide to GitHub CLI for development workflows. Use `--repo owner/repo` when not in a git directory.

## Installation & Setup

```bash
# Install
brew install gh  # macOS
sudo apt install gh  # Linux

# Authenticate
gh auth login

# Setup git integration
gh auth setup-git
```

## Core Commands

### Repository Operations
```bash
gh repo clone owner/repo
gh repo create my-repo --public/--private
gh repo view owner/repo
gh repo list --json name,description
```

### Issues & Pull Requests
```bash
gh issue list --state open
gh issue create --title "Fix bug"
gh pr create --title "Add feature"
gh pr list --json number,title,author
gh pr checkout 123
```

### CI/CD Workflows
```bash
gh run list --limit 5
gh run view <run-id> --log
gh workflow run ci.yml
```

### API Access
```bash
gh api /user
gh api repos/owner/repo/issues --jq '.[].title'
```

## Programmatic Usage

For apps/scripts, focus on JSON output and API endpoints:

```bash
# Get structured data
gh issue list --json number,title,state,labels --jq '.[] | select(.state == "open")'

# API queries for automation
gh api repos/owner/repo/pulls --jq '.[].head.ref'

# Batch operations
gh pr list --json number --jq '.[].number' | xargs -I {} gh pr edit {} --add-label ready
```

## References

- **Authentication**: See `auth.md` for enterprise setup and token management
- **Repository Management**: See `repo-operations.md` for advanced repo workflows
- **CI/CD Integration**: See `ci-cd-automation.md` for workflow automation
- **API Patterns**: See `api-reference.md` for programmatic usage examples
- **Common Scripts**: See `examples.md` for reusable automation patterns

## Environment Variables

```bash
export GH_TOKEN=your_token          # For automation
export GH_HOST=github.com          # Default host
export GH_REPO=owner/repo          # Default repository
export GH_PROMPT_DISABLED=true     # Disable prompts
```

## Quick Tips

- Use `--json` + `--jq` for structured data extraction
- Use `--paginate` for large result sets
- Use `--repo owner/repo` to specify repository explicitly
- Use `gh api` for advanced GitHub API access

**Version**: 2.85.0 (January 2026)
**Docs**: https://cli.github.com/manual/