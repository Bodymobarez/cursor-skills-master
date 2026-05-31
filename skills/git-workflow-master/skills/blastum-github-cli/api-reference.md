# GitHub CLI API Reference

Programmatic patterns for apps and scripts using `gh`.

## JSON Output Patterns

### Basic JSON Extraction
```bash
# Get issue data as JSON
gh issue list --json number,title,state,author,labels

# Extract specific fields with jq
gh issue list --json number,title --jq '.[] | "\(.number): \(.title)"'

# Filter results
gh pr list --json number,title,author --jq '.[] | select(.author.login == "octocat")'
```

### Repository Data
```bash
# Repository info
gh repo view owner/repo --json name,description,defaultBranchRef,updatedAt

# Repository stats
gh api repos/owner/repo --jq '{stars: .stargazers_count, forks: .forks_count, issues: .open_issues_count}'

# Repository languages
gh api repos/owner/repo/languages --jq 'to_entries | sort_by(.value) | reverse | .[0:5]'
```

### Pull Request Data
```bash
# PR with files and commits
gh pr view 123 --json title,body,files,commits,reviews

# PR status checks
gh pr checks 123 --json name,conclusion,status

# PR diff stats
gh api repos/owner/repo/pulls/123 --jq '{additions: .additions, deletions: .deletions, changed_files: .changed_files}'
```

## API Endpoints for Automation

### User/Organization Data
```bash
# Current user info
gh api /user --jq '{login: .login, name: .name, email: .email}'

# Organization members
gh api orgs/organization/members --jq '.[].login'

# Repository collaborators
gh api repos/owner/repo/collaborators --jq '.[].login'
```

### Issue/PR Management
```bash
# Create issue
gh api repos/owner/repo/issues \
  --method POST \
  --field title="Bug report" \
  --field body="Description" \
  --jq '.number'

# Update issue labels
gh api repos/owner/repo/issues/123/labels \
  --method PUT \
  --input <(echo '["bug", "high-priority"]')
```

### Workflow/CI Data
```bash
# Recent workflow runs
gh run list --json databaseId,status,conclusion,headBranch,createdAt

# Workflow run details
gh api repos/owner/repo/actions/runs/123456789 --jq '{status: .status, conclusion: .conclusion}'

# Workflow run jobs
gh api repos/owner/repo/actions/runs/123456789/jobs --jq '.jobs[].name'
```

## Pagination & Rate Limiting

### Handling Large Datasets
```bash
# Paginate through all issues
gh issue list --state all --paginate --json number,title

# Handle API rate limits
gh api /user/repos --paginate | jq '.[] | select(.private == false)'
```

### Batch Processing
```bash
# Process issues in batches
gh issue list --limit 100 --json number --jq '.[].number' | \
  xargs -n 10 -I {} sh -c 'echo "Processing issues: {}"'

# Bulk label updates
gh pr list --state open --json number --jq '.[].number' | \
  xargs -I {} gh pr edit {} --add-label "needs-review"
```

## Error Handling

### Check Command Success
```bash
# Capture exit codes
if gh repo view owner/repo >/dev/null 2>&1; then
  echo "Repository exists"
else
  echo "Repository not found"
fi
```

### Parse Error Responses
```bash
# Handle API errors
response=$(gh api /repos/owner/repo 2>/dev/null) || {
  echo "API call failed"
  exit 1
}
```

## Authentication Patterns

### Token Management
```bash
# Use token from environment
export GH_TOKEN=ghp_your_token_here

# Token for specific host
gh api /user --hostname enterprise.company.com

# Check token scopes
gh auth status --show-token | jq '.tokenScopes'
```

### Enterprise/GitHub Enterprise
```bash
# Set enterprise host
export GH_HOST=github.enterprise.com

# Authenticate to enterprise
gh auth login --hostname github.enterprise.com
```

## Common Data Structures

### Issue Object
```json
{
  "number": 123,
  "title": "Bug report",
  "state": "open",
  "author": {"login": "octocat"},
  "labels": [{"name": "bug"}, {"name": "high-priority"}],
  "created_at": "2024-01-01T00:00:00Z"
}
```

### Pull Request Object
```json
{
  "number": 456,
  "title": "Add feature",
  "state": "open",
  "head": {"ref": "feature-branch"},
  "base": {"ref": "main"},
  "author": {"login": "octocat"},
  "additions": 150,
  "deletions": 25,
  "changed_files": 5
}
```

### Repository Object
```json
{
  "name": "my-repo",
  "full_name": "owner/my-repo",
  "private": false,
  "owner": {"login": "owner"},
  "html_url": "https://github.com/owner/my-repo",
  "description": "Repository description",
  "language": "JavaScript",
  "stargazers_count": 42
}
```

## GraphQL Queries

### Advanced Data Fetching
```bash
# GraphQL query for complex data
gh api graphql -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      issues(first: 10, states: OPEN) {
        nodes {
          number
          title
          author {
            login
          }
        }
      }
    }
  }' -f owner="octocat" -f repo="Hello-World"
```

### Repository Contributors
```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      collaborators(first: 10) {
        nodes {
          login
          name
        }
      }
    }
  }' -f owner="octocat" -f repo="Hello-World"
```