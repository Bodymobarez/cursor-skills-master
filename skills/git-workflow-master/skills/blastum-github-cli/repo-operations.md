# GitHub CLI Repository Operations

Advanced repository management and automation workflows.

## Repository Creation & Setup

### Advanced Repository Creation
```bash
# Create with full configuration
gh repo create my-project \
  --description "Advanced project setup" \
  --homepage "https://myproject.com" \
  --public \
  --license mit \
  --gitignore Python \
  --template owner/template-repo

# Create organization repository
gh repo create org/my-repo --private

# Create with custom settings
gh repo create my-repo \
  --enable-issues=false \
  --enable-wiki=false \
  --enable-projects=true \
  --enable-discussions=true
```

### Repository Templates
```bash
# Mark repository as template
gh repo edit owner/repo --template

# Create from template
gh repo create new-repo --template owner/template-repo

# List available templates
gh repo list owner --json name,isTemplate --jq '.[] | select(.isTemplate == true)'
```

## Repository Management

### Bulk Repository Operations
```bash
# Archive multiple repositories
for repo in repo1 repo2 repo3; do
  gh repo archive owner/$repo
done

# Change visibility for multiple repos
gh repo list owner --json name,isPrivate --jq '.[] | select(.isPrivate == false) | .name' | \
  xargs -I {} gh repo edit owner/{} --visibility private

# Add topic labels to repositories
for repo in $(gh repo list owner --json name --jq '.[].name'); do
  gh repo edit owner/$repo --add-topic "automated"
done
```

### Repository Settings Management
```bash
# Configure repository settings
gh repo edit owner/repo \
  --default-branch develop \
  --enable-merge-commit=false \
  --enable-squash-merge=true \
  --enable-rebase-merge=true \
  --delete-branch-on-merge

# Configure branch protection
# Note: Branch protection requires GitHub API or web interface
gh api repos/owner/repo/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict": true, "contexts": ["ci/build"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count": 1}'
```

## Fork Management

### Advanced Fork Operations
```bash
# Fork with custom settings
gh repo fork owner/repo \
  --org my-org \
  --clone \
  --remote-name upstream \
  --remote

# Sync fork with upstream
gh repo sync --force

# Update fork branch
gh repo sync --branch feature-branch

# Check if fork is up to date
upstream_ahead=$(git rev-list HEAD..upstream/main --count)
if [ "$upstream_ahead" -gt 0 ]; then
  echo "Fork is $upstream_ahead commits behind upstream"
fi
```

### Fork Statistics
```bash
# Get fork information
gh repo view owner/repo --json forksCount,parent

# List all forks of a repository
gh api repos/owner/repo/forks --jq '.[].full_name'

# Check fork sync status
gh api repos/fork-owner/repo/compare/upstream-owner:upstream-branch...fork-owner:fork-branch
```

## Repository Analytics

### Repository Health Metrics
```bash
# Get repository statistics
gh repo view owner/repo --json \
  name,stargazersCount,forksCount,networkCount,watchersCount

# Get contributor statistics
gh api repos/owner/repo/contributors --jq length

# Get language breakdown
gh api repos/owner/repo/languages --jq to_entries | jq 'sort_by(.value) | reverse'

# Get repository activity
gh api repos/owner/repo/stats/commit_activity --jq '.[-5:]'  # Last 5 weeks
```

### Code Analysis
```bash
# Search for specific patterns
gh search code "TODO|FIXME|XXX" --repo owner/repo --json path,lineNumber

# Find large files
gh api repos/owner/repo/git/trees/main?recursive=1 \
  --jq '.tree[] | select(.type == "blob") | {path, size}' | \
  jq 'sort_by(.size) | reverse | .[0:10]'

# Check for binary files
gh api repos/owner/repo/git/trees/main?recursive=1 \
  --jq '.tree[] | select(.type == "blob" and (.path | endswith(".jpg",".png",".gif",".pdf"))) | .path'
```

## Repository Maintenance

### Automated Maintenance Tasks
```bash
# Clean up merged branches
gh pr list --state merged --json headRefName --jq '.[].headRefName' | \
  xargs -I {} git branch -d {}

# Archive old repositories
gh repo list owner --json name,updatedAt --jq '.[] | select(.updatedAt < "2023-01-01") | .name' | \
  xargs -I {} gh repo archive owner/{}

# Update repository descriptions
gh repo list owner --json name,description --jq '.[] | select(.description == null) | .name' | \
  xargs -I {} gh repo edit owner/{} --description "Auto-updated description"
```

### Repository Cleanup Scripts
```bash
#!/bin/bash
# cleanup-repo.sh

REPO="$1"
if [ -z "$REPO" ]; then
  echo "Usage: $0 owner/repo"
  exit 1
fi

echo "Cleaning up $REPO..."

# Remove stale branches
echo "Removing merged branches..."
gh pr list --repo "$REPO" --state merged --json headRefName --jq '.[].headRefName' | \
  xargs -I {} gh api repos/"$REPO"/git/refs/heads/{} --method DELETE 2>/dev/null || true

# Archive old issues
echo "Archiving old closed issues..."
gh issue list --repo "$REPO" --state closed --updated-before "2023-01-01" --limit 100 --json number | \
  jq '.[].number' | \
  xargs -I {} gh issue edit {} --repo "$REPO" --add-label "archived"

echo "Cleanup complete!"
```

## Repository Migration

### Migrate Repository Settings
```bash
# Export repository settings
SOURCE_REPO="old-owner/repo"
TARGET_REPO="new-owner/repo"

# Copy labels
gh label list --repo "$SOURCE_REPO" --json name,color,description | \
  jq -r '.[] | @base64' | \
  while read -r label; do
    data=$(echo "$label" | base64 -d)
    name=$(echo "$data" | jq -r '.name')
    color=$(echo "$data" | jq -r '.color')
    desc=$(echo "$data" | jq -r '.description')
    gh label create "$name" --repo "$TARGET_REPO" --color "$color" --description "$desc"
  done
```

### Repository Transfer
```bash
# Transfer repository ownership
gh repo transfer new-owner/repo

# Transfer to organization
gh repo transfer my-org/repo

# Accept transfer (if pending)
gh repo transfer --accept
```

## Repository Automation

### Automated Repository Setup
```bash
#!/bin/bash
# setup-new-repo.sh

REPO_NAME="$1"
ORG="$2"
TEMPLATE="${3:-}"

if [ -z "$REPO_NAME" ] || [ -z "$ORG" ]; then
  echo "Usage: $0 repo-name organization [template]"
  exit 1
fi

echo "Setting up $ORG/$REPO_NAME..."

# Create repository
if [ -n "$TEMPLATE" ]; then
  gh repo create "$ORG/$REPO_NAME" --template "$TEMPLATE" --private
else
  gh repo create "$ORG/$REPO_NAME" --private
fi

# Setup branch protection
gh api repos/"$ORG/$REPO_NAME"/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict": true, "contexts": ["ci"]}' \
  --field required_pull_request_reviews='{"required_approving_review_count": 1}' \
  --field enforce_admins=true

# Add default labels
gh label create "$ORG/$REPO_NAME" bug --color "d73a49" --description "Something isn't working"
gh label create "$ORG/$REPO_NAME" enhancement --color "a2eeef" --description "New feature or request"

# Create initial README
echo "# $REPO_NAME

Auto-generated repository setup.
" | gh api repos/"$ORG/$REPO_NAME"/contents/README.md \
  --method PUT \
  --field message="Initial commit" \
  --field content="$(echo 'Auto-generated repository' | base64)"

echo "Repository setup complete!"
```

### Repository Monitoring
```bash
# Monitor repository changes
gh api repos/owner/repo/events --jq '.[0:5] | .[] | "\(.type): \(.created_at)"'

# Check for new contributors
gh api repos/owner/repo/stats/contributors | \
  jq '.[] | select(.weeks[-1].c > 0) | .author.login'

# Monitor repository size
gh api repos/owner/repo --jq '{size: .size, network_count: .network_count}'
```

## Advanced Repository Features

### Repository Rulesets
```bash
# List rulesets
gh ruleset list --repo owner/repo

# View ruleset
gh ruleset view 123 --repo owner/repo

# Check if branch complies with ruleset
gh ruleset check --repo owner/repo --branch feature-branch
```

### Repository Autolinks
```bash
# List autolinks
gh repo autolink list --repo owner/repo

# Add autolink for Jira tickets
gh repo autolink add --repo owner/repo \
  --key-prefix JIRA- \
  --url-template https://company.atlassian.net/browse/<num>

# Delete autolink
gh repo autolink delete 123 --repo owner/repo
```

### Repository Webhooks
```bash
# List webhooks (requires API)
gh api repos/owner/repo/hooks

# Create webhook
gh api repos/owner/repo/hooks \
  --method POST \
  --field name=web \
  --field active=true \
  --field events='["push", "pull_request"]' \
  --field config='{"url": "https://example.com/webhook", "content_type": "json"}'
```

## Organization-Level Operations

### Organization Repository Management
```bash
# List all organization repositories
gh repo list my-org --limit 200

# Get repository statistics across organization
gh repo list my-org --json name,isPrivate,updatedAt,stargazersCount | \
  jq 'group_by(.isPrivate) | map({private: .[0].isPrivate, count: length})'

# Bulk update repository settings
gh repo list my-org --json name | \
  jq -r '.[].name' | \
  xargs -I {} gh repo edit my-org/{} --enable-dependabot-alerts
```

### Organization Templates
```bash
# Create organization-wide template
gh repo create my-org/template-repo --template

# List organization templates
gh repo list my-org --json name,isTemplate | \
  jq '.[] | select(.isTemplate == true)'
```