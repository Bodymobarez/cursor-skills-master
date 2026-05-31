# GitHub CLI Skill Collection

A comprehensive, consolidated GitHub CLI skill for development workflows. This skill combines the best of multiple GitHub CLI resources into a concise main reference with specialized guides.

## Structure

```
github-cli/
├── SKILL.md              # Main skill - concise core functionality
├── README.md             # This file - documentation overview
├── api-reference.md      # Programmatic usage patterns for apps/scripts
├── examples.md           # Reusable automation scripts and patterns
├── ci-cd-automation.md   # CI/CD pipeline integration
├── auth.md               # Authentication and security patterns
├── repo-operations.md    # Advanced repository management
└── automation.md         # General automation patterns and best practices
```

## Quick Start

1. **Install GitHub CLI**:
   ```bash
   brew install gh  # macOS
   sudo apt install gh  # Linux
   ```

2. **Authenticate**:
   ```bash
   gh auth login
   ```

3. **Basic Usage**:
   ```bash
   gh repo clone owner/repo
   gh issue list --state open
   gh pr create --title "Add feature"
   ```

## File Guide

### SKILL.md - Core Reference
- Installation and setup
- Essential commands for repos, issues, PRs, CI/CD
- Environment variables and configuration
- References to specialized guides

### api-reference.md - Programmatic Usage
- JSON output patterns and data structures
- API endpoints for automation
- Pagination and error handling
- GraphQL queries for complex data

### examples.md - Ready-to-Use Scripts
- Repository health monitoring
- Issue/PR triage automation
- Release management scripts
- Bulk operations and data processing
- Node.js integration examples

### ci-cd-automation.md - Pipeline Integration
- GitHub Actions workflows
- Jenkins, CircleCI, and other CI/CD systems
- Automated deployment tracking
- Security scanning integration

### auth.md - Authentication & Security
- Personal access tokens and scopes
- GitHub Enterprise setup
- SSH key management
- Multi-account and organization patterns

### repo-operations.md - Repository Management
- Advanced repo creation and configuration
- Fork management and synchronization
- Repository analytics and health metrics
- Bulk operations across repositories

### automation.md - Development Patterns
- Script templates and error handling
- Batch processing and parallel execution
- Configuration management
- Monitoring, alerting, and logging

## Use Cases

### For Developers
- **Repository Setup**: Use `SKILL.md` + `repo-operations.md`
- **Daily Workflow**: Core commands in `SKILL.md`
- **Scripting**: Patterns in `examples.md` and `api-reference.md`

### For DevOps/Platform Teams
- **CI/CD Integration**: `ci-cd-automation.md`
- **Automation**: `automation.md` + `examples.md`
- **Security**: `auth.md`

### For App Developers
- **API Integration**: `api-reference.md`
- **Data Processing**: JSON patterns throughout
- **Error Handling**: Robust patterns in `automation.md`

## Key Features

- **Concise Main Reference**: `SKILL.md` provides quick access to essentials
- **Specialized Deep Dives**: Separate files for advanced topics
- **Programmatic Focus**: Strong emphasis on API usage for applications
- **Production Ready**: Includes error handling, monitoring, and best practices
- **CI/CD Integration**: Comprehensive pipeline automation patterns

## Contributing

This is a consolidated skill combining:
- Original `gh-cli` skill (comprehensive reference)
- Original `github` skill (focused practical examples)
- Additional patterns for enterprise and automation use cases

## Version

GitHub CLI: 2.85.0 (January 2026)
Skill Structure: Consolidated Reference v1.0