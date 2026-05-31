# GitHub CLI Authentication Guide

Advanced authentication patterns for different environments and use cases.

## Personal Access Tokens

### Creating Tokens
1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Generate new token (classic or fine-grained)
3. Copy token (you won't see it again)

### Token Scopes
For different operations, ensure your token has these scopes:

```
# Repository operations
repo              # Full repository access
public_repo       # Public repository access only

# Issue/PR operations
repo              # Issues and PRs
public_repo       # Public issues/PRs only

# Organization operations
read:org          # Read org info
write:org         # Modify org settings
admin:org         # Full org admin

# Workflow/CI operations
repo              # Workflows and runs
public_repo       # Public repo workflows
```

### Environment Setup
```bash
# Set token for current session
export GH_TOKEN=ghp_your_token_here

# Or login interactively
gh auth login

# Check authentication status
gh auth status

# View token scopes
gh auth token
```

## GitHub Enterprise Server

### Enterprise Authentication
```bash
# Login to GitHub Enterprise
gh auth login --hostname your-github-enterprise.com

# Set enterprise host
export GH_HOST=your-github-enterprise.com

# Verify connection
gh auth status --hostname your-github-enterprise.com
```

### Multiple Accounts
```bash
# Switch between accounts
gh auth switch

# Or specify account explicitly
gh auth switch --hostname github.com --user yourusername

# View all authenticated accounts
gh auth status
```

## SSH Key Authentication

### Setup SSH Keys
```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add to GitHub
gh ssh-key add ~/.ssh/id_ed25519.pub

# Test connection
ssh -T git@github.com
```

### SSH with GitHub CLI
```bash
# GitHub CLI will use SSH for git operations
gh auth setup-git

# Check SSH setup
gh auth status
```

## GitHub Apps

### App Authentication (for automation)
```bash
# Use GitHub App installation token
export GH_TOKEN=github_app_installation_token

# Or generate token programmatically
# (requires app private key)
```

### App Permissions
Configure these permissions in your GitHub App:

```
# Repository permissions
Contents: Read
Issues: Read & Write
Pull requests: Read & Write
Metadata: Read

# Organization permissions
Members: Read
Projects: Read & Write
```

## OAuth Device Flow

### For headless environments
```bash
# Start device flow
gh auth login --web --device

# Follow the URL and enter code
# CLI will automatically complete authentication
```

## Security Best Practices

### Token Management
```bash
# Never commit tokens to version control
# Use environment variables or secret managers

# Rotate tokens regularly
gh auth refresh

# Revoke compromised tokens immediately
# Go to GitHub Settings → Developer settings → Personal access tokens
```

### Environment Variables
```bash
# Use different tokens for different environments
export GH_TOKEN_PROD=ghp_prod_token
export GH_TOKEN_DEV=ghp_dev_token

# Switch tokens as needed
export GH_TOKEN=$GH_TOKEN_PROD
```

### Secure Token Storage
```bash
# Use keyring/credential manager
gh auth login --secure-storage

# Or use environment variables in CI/CD
# Never echo tokens in logs
```

## Troubleshooting Authentication

### Common Issues

**"Authentication failed"**
```bash
# Check token validity
gh auth status

# Verify token scopes
curl -H "Authorization: token $GH_TOKEN" https://api.github.com/user

# Check token expiration (fine-grained tokens expire)
```

**"Repository not found"**
```bash
# Verify repository access
gh repo view owner/repo

# Check if token has repo scope
gh auth status --show-token
```

**"Rate limit exceeded"**
```bash
# Check rate limit status
curl -H "Authorization: token $GH_TOKEN" https://api.github.com/rate_limit

# Wait or use different token
# Consider using GitHub App for higher limits
```

### Debug Mode
```bash
# Enable debug output
gh api /user --verbose

# View HTTP requests
gh api /user --include
```

## Enterprise Authentication Patterns

### SAML SSO
```bash
# For organizations with SAML
gh auth login --web

# Authorize the OAuth App for your organization
# Follow SAML authentication flow
```

### LDAP Integration
```bash
# Use enterprise username/password
gh auth login --hostname enterprise.company.com

# Or use personal access token
export GH_TOKEN=enterprise_token
export GH_HOST=enterprise.company.com
```

## CI/CD Authentication

### GitHub Actions
```yaml
- name: Setup GitHub CLI
  uses: actions/setup-gh@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}

# Token is automatically available
# No additional setup needed
```

### Other CI Systems
```bash
# Set token as environment variable
export GH_TOKEN=${GITHUB_TOKEN}

# Or use repository secret
export GH_TOKEN=$(cat /secrets/github-token)
```

### Service Account Pattern
```bash
# Use dedicated service account
export GH_TOKEN=ghp_service_account_token

# Service account should have minimal required permissions
# Rotate regularly
```

## Multi-Organization Setup

### Organization-Specific Tokens
```bash
# Different tokens for different orgs
export GH_TOKEN_ORG1=ghp_org1_token
export GH_TOKEN_ORG2=ghp_org2_token

# Switch contexts
export GH_TOKEN=$GH_TOKEN_ORG1
export GH_REPO=org1/repo

export GH_TOKEN=$GH_TOKEN_ORG2
export GH_REPO=org2/repo
```

### Context Switching Script
```bash
#!/bin/bash
# switch-org.sh

ORG="$1"
if [ -z "$ORG" ]; then
  echo "Usage: $0 organization"
  exit 1
fi

case "$ORG" in
  "work")
    export GH_TOKEN=$WORK_TOKEN
    export GH_REPO=$WORK_DEFAULT_REPO
    ;;
  "personal")
    export GH_TOKEN=$PERSONAL_TOKEN
    export GH_REPO=$PERSONAL_DEFAULT_REPO
    ;;
  *)
    echo "Unknown organization: $ORG"
    exit 1
    ;;
esac

echo "Switched to $ORG context"
gh auth status
```