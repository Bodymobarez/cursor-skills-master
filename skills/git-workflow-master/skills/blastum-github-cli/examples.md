# GitHub CLI Examples

Reusable patterns for scripts and applications.

## Repository Health Check

```bash
#!/bin/bash
# repo-health.sh - Check repository health metrics

REPO="$1"
if [ -z "$REPO" ]; then
  echo "Usage: $0 owner/repo"
  exit 1
fi

echo "=== Repository Health Check: $REPO ==="

# Basic repo info
gh repo view "$REPO" --json name,description,stargazersCount,forksCount,updatedAt

# Open issues count
open_issues=$(gh issue list --repo "$REPO" --state open --json number --jq length)
echo "Open issues: $open_issues"

# Open PRs count
open_prs=$(gh pr list --repo "$REPO" --state open --json number --jq length)
echo "Open PRs: $open_prs"

# Recent activity (last 30 days)
recent_issues=$(gh issue list --repo "$REPO" --state all --since "30 days ago" --json number --jq length)
echo "Issues created in last 30 days: $recent_issues"
```

## Pull Request Status Monitor

```bash
#!/bin/bash
# pr-monitor.sh - Monitor PR status for CI/CD

REPO="$1"
if [ -z "$REPO" ]; then
  echo "Usage: $0 owner/repo"
  exit 1
fi

echo "=== PR Status Monitor: $REPO ==="

# Get PRs with failing checks
gh pr list --repo "$REPO" --state open --json number,title,author,headRefName | \
  jq -r '.[] | "\(.number)\t\(.title)\t\(.author.login)\t\(.headRefName)"' | \
  while IFS=$'\t' read -r number title author branch; do
    echo "PR #$number: $title (by $author)"

    # Check CI status
    checks=$(gh pr checks "$number" --repo "$REPO" --json conclusion,status,name 2>/dev/null)
    if [ $? -eq 0 ]; then
      failures=$(echo "$checks" | jq '[.[] | select(.conclusion == "failure")] | length')
      if [ "$failures" -gt 0 ]; then
        echo "  ❌ $failures failing checks"
      else
        echo "  ✅ All checks passing"
      fi
    else
      echo "  ⚠️  No checks configured"
    fi
    echo
  done
```

## Issue Triage Script

```bash
#!/bin/bash
# issue-triage.sh - Automated issue labeling and triage

REPO="$1"
if [ -z "$REPO" ]; then
  echo "Usage: $0 owner/repo"
  exit 1
fi

echo "=== Issue Triage: $REPO ==="

# Label issues based on content analysis
gh issue list --repo "$REPO" --state open --limit 50 --json number,title,body | \
  jq -c '.[]' | \
  while read -r issue; do
    number=$(echo "$issue" | jq -r '.number')
    title=$(echo "$issue" | jq -r '.title')
    body=$(echo "$issue" | jq -r '.body // ""')

    echo "Processing issue #$number: $title"

    # Bug detection
    if echo "$title $body" | grep -qi "bug\|error\|crash\|fail"; then
      gh issue edit "$number" --repo "$REPO" --add-label "bug"
      echo "  Added 'bug' label"
    fi

    # Feature request detection
    if echo "$title $body" | grep -qi "feature\|add\|request\|enhancement"; then
      gh issue edit "$number" --repo "$REPO" --add-label "enhancement"
      echo "  Added 'enhancement' label"
    fi

    # Question detection
    if echo "$title $body" | grep -qi "how\|what\|why\|question\|help"; then
      gh issue edit "$number" --repo "$REPO" --add-label "question"
      echo "  Added 'question' label"
    fi
  done
```

## Release Automation

```bash
#!/bin/bash
# create-release.sh - Automated release creation

REPO="$1"
TAG="$2"
if [ -z "$REPO" ] || [ -z "$TAG" ]; then
  echo "Usage: $0 owner/repo v1.0.0"
  exit 1
fi

echo "=== Creating Release: $TAG for $REPO ==="

# Generate release notes from PRs
release_notes=$(gh pr list --repo "$REPO" --state merged --json number,title,author --limit 20 | \
  jq -r '.[] | "- \(.title) (#\(.number)) by @\(.author.login)"' | \
  tr '\n' '\n')

# Create release
gh release create "$TAG" \
  --repo "$REPO" \
  --title "Release $TAG" \
  --notes "$release_notes" \
  --generate-notes

if [ $? -eq 0 ]; then
  echo "✅ Release $TAG created successfully"
else
  echo "❌ Failed to create release"
  exit 1
fi
```

## Contributor Statistics

```bash
#!/bin/bash
# contributor-stats.sh - Generate contributor statistics

REPO="$1"
DAYS="${2:-90}"

if [ -z "$REPO" ]; then
  echo "Usage: $0 owner/repo [days=90]"
  exit 1
fi

echo "=== Contributor Stats: $REPO (last $DAYS days) ==="

# Commits by author
echo "Commits by author:"
gh api "repos/$REPO/commits?since=$(date -v-${DAYS}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)" | \
  jq -r '.[].author.login' | \
  sort | uniq -c | sort -nr | \
  head -10 | \
  awk '{print $2 ": " $1 " commits"}'

echo

# Issues created
echo "Issues created:"
gh issue list --repo "$REPO" --author "@me" --since "${DAYS} days ago" --json number --jq length
echo " issues"

# PRs created
echo "PRs created:"
gh pr list --repo "$REPO" --author "@me" --since "${DAYS} days ago" --json number --jq length
echo " PRs"
```

## Bulk Repository Operations

```bash
#!/bin/bash
# bulk-repo-ops.sh - Operations across multiple repositories

ORG="$1"
OPERATION="$2"

if [ -z "$ORG" ] || [ -z "$OPERATION" ]; then
  echo "Usage: $0 organization operation"
  echo "Operations: list, archive, unarchive, private, public"
  exit 1
fi

echo "=== Bulk Repository Operations: $ORG ($OPERATION) ==="

# Get all repositories
repos=$(gh repo list "$ORG" --json name --jq '.[].name')

for repo in $repos; do
  echo "Processing $ORG/$repo..."

  case "$OPERATION" in
    "list")
      echo "  $repo"
      ;;
    "archive")
      gh repo archive "$ORG/$repo" --yes
      echo "  ✅ Archived"
      ;;
    "unarchive")
      gh repo unarchive "$ORG/$repo"
      echo "  ✅ Unarchived"
      ;;
    "private")
      gh repo edit "$ORG/$repo" --visibility private
      echo "  ✅ Made private"
      ;;
    "public")
      gh repo edit "$ORG/$repo" --visibility public
      echo "  ✅ Made public"
      ;;
    *)
      echo "  ❌ Unknown operation: $OPERATION"
      ;;
  esac
done
```

## CI/CD Pipeline Status

```bash
#!/bin/bash
# pipeline-status.sh - Check CI/CD pipeline status

REPO="$1"
BRANCH="${2:-main}"

if [ -z "$REPO" ]; then
  echo "Usage: $0 owner/repo [branch=main]"
  exit 1
fi

echo "=== Pipeline Status: $REPO ($BRANCH) ==="

# Get latest workflow runs for branch
latest_run=$(gh run list --repo "$REPO" --branch "$BRANCH" --limit 1 --json databaseId,status,conclusion,createdAt,updatedAt)

if [ "$(echo "$latest_run" | jq length)" -eq 0 ]; then
  echo "No workflow runs found for branch $BRANCH"
  exit 1
fi

run_id=$(echo "$latest_run" | jq -r '.[0].databaseId')
status=$(echo "$latest_run" | jq -r '.[0].status')
conclusion=$(echo "$latest_run" | jq -r '.[0].conclusion')
created=$(echo "$latest_run" | jq -r '.[0].createdAt')
updated=$(echo "$latest_run" | jq -r '.[0].updatedAt')

echo "Latest run: #$run_id"
echo "Status: $status"
echo "Conclusion: $conclusion"
echo "Created: $created"
echo "Updated: $updated"

# Show job status if running or completed
if [ "$status" != "completed" ]; then
  echo "Current jobs:"
  gh run view "$run_id" --repo "$REPO" --json jobs --jq '.jobs[] | "\(.name): \(.status) \(.conclusion // "")"'
fi
```

## Node.js Integration Example

```javascript
// github-integration.js - Node.js GitHub CLI integration

const { execSync } = require('child_process');
const path = require('path');

class GitHubCLI {
  constructor(repo, token = null) {
    this.repo = repo;
    this.token = token;
  }

  exec(command) {
    const env = { ...process.env };
    if (this.token) {
      env.GH_TOKEN = this.token;
    }
    if (this.repo) {
      env.GH_REPO = this.repo;
    }

    try {
      return execSync(`gh ${command}`, {
        encoding: 'utf8',
        env,
        stdio: 'pipe'
      });
    } catch (error) {
      throw new Error(`GitHub CLI command failed: ${error.message}`);
    }
  }

  // Get repository info
  async getRepoInfo() {
    const output = this.exec('repo view --json name,description,stargazersCount');
    return JSON.parse(output);
  }

  // List open issues
  async getOpenIssues(limit = 10) {
    const output = this.exec(`issue list --state open --limit ${limit} --json number,title,author`);
    return JSON.parse(output);
  }

  // Create an issue
  async createIssue(title, body, labels = []) {
    let cmd = `issue create --title "${title}" --body "${body}"`;
    if (labels.length > 0) {
      cmd += ` --labels "${labels.join(',')}"`;
    }
    const output = this.exec(cmd);
    // Extract issue number from output
    const match = output.match(/issues\/(\d+)/);
    return match ? parseInt(match[1]) : null;
  }

  // Check PR status
  async getPRStatus(prNumber) {
    const output = this.exec(`pr checks ${prNumber} --json conclusion,status,name`);
    return JSON.parse(output);
  }
}

// Usage example
async function main() {
  const gh = new GitHubCLI('octocat/Hello-World');

  try {
    const repo = await gh.getRepoInfo();
    console.log(`Repository: ${repo.name}`);
    console.log(`Stars: ${repo.stargazersCount}`);

    const issues = await gh.getOpenIssues(5);
    console.log(`\nOpen issues (${issues.length}):`);
    issues.forEach(issue => {
      console.log(`#${issue.number}: ${issue.title}`);
    });
  } catch (error) {
    console.error('Error:', error.message);
  }
}

if (require.main === module) {
  main();
}

module.exports = GitHubCLI;
```