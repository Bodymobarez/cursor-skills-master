# GitHub CLI CI/CD Automation

Integrate GitHub CLI into your CI/CD pipelines for enhanced automation.

## GitHub Actions Integration

### Basic Setup
```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup GitHub CLI
        uses: actions/setup-gh@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Run tests
        run: npm test

      - name: Create issue on failure
        if: failure()
        run: |
          gh issue create \
            --title "CI failed on ${{ github.ref_name }}" \
            --body "Build failed: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}" \
            --labels "bug,ci-failure"
```

### PR Validation Workflow
```yaml
# .github/workflows/pr-validation.yml
name: PR Validation
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup GitHub CLI
        uses: actions/setup-gh@v1

      - name: Check PR size
        run: |
          files_changed=$(gh pr view ${{ github.event.pull_request.number }} --json files --jq '.files | length')
          if [ "$files_changed" -gt 50 ]; then
            gh pr comment ${{ github.event.pull_request.number }} \
              --body "⚠️ Large PR detected ($files_changed files changed). Consider breaking into smaller PRs."
          fi

      - name: Validate PR description
        run: |
          body=$(gh pr view ${{ github.event.pull_request.number }} --json body --jq '.body')
          if [ -z "$body" ] || [ "$body" = "null" ]; then
            gh pr comment ${{ github.event.pull_request.number }} \
              --body "❌ PR description is required. Please add a description explaining your changes."
            exit 1
          fi
```

### Release Automation
```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup GitHub CLI
        uses: actions/setup-gh@v1

      - name: Generate release notes
        run: |
          # Get merged PRs since last release
          prs=$(gh pr list --state merged --json number,title,author --limit 20 | \
            jq -r '.[] | "- \(.title) (#\(.number)) by @\(.author.login)"')

          # Create release
          gh release create ${{ github.ref_name }} \
            --title "Release ${{ github.ref_name }}" \
            --notes "$prs" \
            --generate-notes
```

## Docker Integration

### Dockerfile with GitHub CLI
```dockerfile
FROM node:18-alpine

# Install GitHub CLI
RUN apk add --no-cache github-cli

# Copy application
COPY . /app
WORKDIR /app

# Set GitHub token (passed at runtime)
ENV GH_TOKEN=""

CMD ["npm", "start"]
```

### Docker Compose Setup
```yaml
version: '3.8'
services:
  ci-runner:
    build: .
    environment:
      - GH_TOKEN=${GH_TOKEN}
      - GH_REPO=${GH_REPO}
    volumes:
      - .:/app
    command: sh -c "gh auth status && npm run ci"
```

## Jenkins Integration

### Jenkins Pipeline
```groovy
pipeline {
    agent any

    environment {
        GH_TOKEN = credentials('github-token')
        GH_REPO = 'owner/repo'
    }

    stages {
        stage('Setup') {
            steps {
                sh '''
                    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt update && sudo apt install -y gh
                '''
            }
        }

        stage('Test') {
            steps {
                sh 'npm test'
            }
            post {
                failure {
                    sh '''
                        gh issue create \
                          --title "Jenkins build failed: ${JOB_NAME} #${BUILD_NUMBER}" \
                          --body "Build failed: ${BUILD_URL}" \
                          --labels "ci-failure"
                    '''
                }
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                sh '''
                    # Get latest release info
                    latest_release=$(gh release view --json tagName --jq .tagName)
                    echo "Latest release: $latest_release"

                    # Update deployment status
                    gh api repos/${GH_REPO}/deployments \
                      --method POST \
                      --field ref="${GIT_COMMIT}" \
                      --field environment="production"
                '''
            }
        }
    }
}
```

## CircleCI Integration

### CircleCI Config
```yaml
version: 2.1

executors:
  gh-cli:
    docker:
      - image: cimg/node:18
    environment:
      GH_REPO: owner/repo

commands:
  setup-gh:
    steps:
      - run:
          name: Install GitHub CLI
          command: |
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            sudo apt update && sudo apt install -y gh

jobs:
  test:
    executor: gh-cli
    steps:
      - checkout
      - setup-gh
      - run:
          name: Authenticate with GitHub
          command: echo $GH_TOKEN | gh auth login --with-token

      - run:
          name: Run tests
          command: npm test

      - run:
          name: Report test results
          command: |
            if [ $? -eq 0 ]; then
              gh issue create --title "✅ Tests passed on ${CIRCLE_BRANCH}" --body "All tests passed in CI"
            else
              gh issue create --title "❌ Tests failed on ${CIRCLE_BRANCH}" --body "Tests failed: ${CIRCLE_BUILD_URL}"
            fi
          when: always
```

## Automated Dependency Updates

### Dependabot Integration
```yaml
# .github/workflows/dependabot-automerge.yml
name: Dependabot Auto-Merge
on:
  pull_request:
    branches:
      - main

jobs:
  dependabot:
    runs-on: ubuntu-latest
    if: github.actor == 'dependabot[bot]'
    steps:
      - uses: actions/checkout@v4

      - name: Setup GitHub CLI
        uses: actions/setup-gh@v1

      - name: Auto-approve and merge Dependabot PRs
        run: |
          # Check if PR is from Dependabot
          if gh pr view ${{ github.event.pull_request.number }} --json author --jq '.author.login' | grep -q "dependabot"; then
            # Approve the PR
            gh pr review ${{ github.event.pull_request.number }} --approve --body "🤖 Auto-approved by CI"

            # Enable auto-merge if available
            gh pr merge ${{ github.event.pull_request.number }} --auto --merge
          fi
```

## Custom CI/CD Scripts

### Release Preparation Script
```bash
#!/bin/bash
# prepare-release.sh

set -e

REPO="$1"
NEW_VERSION="$2"

if [ -z "$REPO" ] || [ -z "$NEW_VERSION" ]; then
  echo "Usage: $0 owner/repo v1.2.3"
  exit 1
fi

echo "Preparing release $NEW_VERSION for $REPO"

# Create release branch
gh repo sync
git checkout -b "release/$NEW_VERSION"

# Update version files
echo "$NEW_VERSION" > VERSION
npm version "$NEW_VERSION" --no-git-tag-version

# Commit changes
git add VERSION package.json
git commit -m "Bump version to $NEW_VERSION"

# Push branch
git push origin "release/$NEW_VERSION"

# Create PR
pr_url=$(gh pr create \
  --title "Release $NEW_VERSION" \
  --body "Automated release preparation for version $NEW_VERSION" \
  --base main \
  --head "release/$NEW_VERSION" \
  --label "release" \
  --jq '.url')

echo "Created PR: $pr_url"
```

### Deployment Status Tracking
```bash
#!/bin/bash
# deployment-status.sh

REPO="$1"
ENVIRONMENT="$2"
STATUS="$3"  # success|failure|in_progress

if [ -z "$REPO" ] || [ -z "$ENVIRONMENT" ] || [ -z "$STATUS" ]; then
  echo "Usage: $0 owner/repo production success"
  exit 1
fi

# Create deployment status
gh api repos/$REPO/deployments \
  --method POST \
  --field ref="$GITHUB_SHA" \
  --field environment="$ENVIRONMENT" \
  --field description="Deployment to $ENVIRONMENT" \
  --jq '.id' | \
  xargs -I {} gh api repos/$REPO/deployments/{}/statuses \
    --method POST \
    --field state="$STATUS" \
    --field description="Deployment $STATUS"
```

## Monitoring and Alerting

### Health Check Workflow
```yaml
# .github/workflows/health-check.yml
name: Health Check
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  health:
    runs-on: ubuntu-latest
    steps:
      - name: Setup GitHub CLI
        uses: actions/setup-gh@v1

      - name: Check repository health
        run: |
          # Check for stale issues
          stale_issues=$(gh issue list --state open --search "updated:<$(date -d '30 days ago' +%Y-%m-%d)" --json number --jq length)

          if [ "$stale_issues" -gt 10 ]; then
            gh issue create \
              --title "⚠️ High number of stale issues: $stale_issues" \
              --body "Repository has $stale_issues issues not updated in 30+ days" \
              --labels "maintenance"
          fi

      - name: Check PR review status
        run: |
          # Find PRs without reviews
          unreviewed=$(gh pr list --state open --search "review:none" --json number --jq length)

          if [ "$unreviewed" -gt 0 ]; then
            echo "Found $unreviewed PRs awaiting review"
            # Could send notifications or create tracking issues
          fi
```

### Performance Monitoring
```yaml
# .github/workflows/performance.yml
name: Performance Monitoring
on:
  push:
    branches: [main]

jobs:
  perf:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup GitHub CLI
        uses: actions/setup-gh@v1

      - name: Run performance tests
        run: |
          # Run benchmarks
          npm run bench

          # Create issue if performance degraded
          if [ -f benchmark-results.json ]; then
            # Parse results and check thresholds
            regression=$(jq '.regressionDetected' benchmark-results.json)

            if [ "$regression" = "true" ]; then
              gh issue create \
                --title "⚠️ Performance regression detected" \
                --body "Performance tests detected a regression in the latest commit" \
                --labels "performance"
            fi
          fi
```

## Security Integration

### Vulnerability Scanning
```yaml
# .github/workflows/security-scan.yml
name: Security Scan
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
  push:
    branches: [main]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup GitHub CLI
        uses: actions/setup-gh@v1

      - name: Run security scan
        run: |
          # Use GitHub's security features
          vulnerabilities=$(gh api repos/${{ github.repository }}/vulnerability-alerts --jq length)

          if [ "$vulnerabilities" -gt 0 ]; then
            gh issue create \
              --title "🚨 Security vulnerabilities detected" \
              --body "Found $vulnerabilities security vulnerabilities that need attention" \
              --labels "security,urgent"
          fi

      - name: Check for exposed secrets
        run: |
          # Scan for potential secrets in code
          if command -v gitleaks >/dev/null 2>&1; then
            gitleaks detect --verbose --redact

            if [ $? -ne 0 ]; then
              gh issue create \
                --title "🚨 Potential secrets detected in code" \
                --body "Secret scanning detected potential exposed credentials" \
                --labels "security"
            fi
          fi
```

## Best Practices for CI/CD Integration

1. **Token Management**
   - Use GitHub App tokens for better permission control
   - Rotate tokens regularly
   - Use repository secrets for sensitive tokens

2. **Error Handling**
   - Always check command exit codes
   - Use `set -e` in bash scripts
   - Implement retry logic for transient failures

3. **Rate Limiting**
   - Be aware of GitHub API rate limits
   - Use `--paginate` for large result sets
   - Implement exponential backoff for retries

4. **Logging and Monitoring**
   - Log all API calls for debugging
   - Monitor workflow success rates
   - Set up alerts for failed automations

5. **Security Considerations**
   - Never log tokens or sensitive data
   - Use `--repo` flag to avoid repository confusion
   - Validate all inputs before processing