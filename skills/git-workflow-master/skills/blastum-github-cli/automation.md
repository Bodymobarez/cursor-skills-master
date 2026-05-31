# GitHub CLI Automation Patterns

Common automation patterns for scripts and applications using GitHub CLI.

## Script Structure Patterns

### Basic Script Template
```bash
#!/bin/bash
# template.sh - GitHub CLI automation template

set -euo pipefail

# Configuration
REPO="${REPO:-}"
TOKEN="${GH_TOKEN:-}"

# Logging functions
log_info() { echo "[INFO] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }

# Validation
validate_inputs() {
  if [ -z "$REPO" ]; then
    log_error "REPO environment variable is required"
    exit 1
  fi

  if [ -z "$TOKEN" ]; then
    log_error "GH_TOKEN environment variable is required"
    exit 1
  fi

  # Verify authentication
  if ! gh auth status >/dev/null 2>&1; then
    log_error "GitHub CLI authentication failed"
    exit 1
  fi
}

# Main function
main() {
  validate_inputs

  log_info "Starting automation for $REPO"

  # Your automation logic here
  gh repo view "$REPO" --json name,description

  log_info "Automation completed successfully"
}

# Run main function
main "$@"
```

## Error Handling Patterns

### Retry Logic
```bash
#!/bin/bash
# retry.sh - Commands with retry logic

retry_command() {
  local cmd="$1"
  local max_attempts="${2:-3}"
  local delay="${3:-5}"
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    log_info "Attempt $attempt/$max_attempts: $cmd"

    if eval "$cmd"; then
      return 0
    else
      log_warn "Command failed (attempt $attempt/$max_attempts)"

      if [ $attempt -eq $max_attempts ]; then
        log_error "Command failed after $max_attempts attempts"
        return 1
      fi

      sleep $delay
      delay=$((delay * 2))  # Exponential backoff
      attempt=$((attempt + 1))
    fi
  done
}

# Usage
retry_command "gh api /user" 3 2
```

### Graceful Degradation
```bash
#!/bin/bash
# graceful.sh - Handle failures gracefully

get_repo_info() {
  local repo="$1"

  if ! repo_data=$(gh repo view "$repo" --json name,description 2>/dev/null); then
    log_warn "Could not fetch repository info for $repo"
    echo '{"name": "unknown", "description": "Repository info unavailable"}'
    return 1
  fi

  echo "$repo_data"
}

# Usage
repo_info=$(get_repo_info "owner/repo" || echo '{"error": "failed to fetch"}')
name=$(echo "$repo_info" | jq -r '.name // "unknown"')
```

## Data Processing Patterns

### Batch Processing
```bash
#!/bin/bash
# batch-process.sh - Process items in batches

process_batch() {
  local items="$1"
  local batch_size="${2:-10}"

  echo "$items" | jq -c '.[]' | \
    xargs -n 1 -P "$batch_size" -I {} sh -c '
      item="$1"
      # Process individual item
      number=$(echo "$item" | jq -r ".number")
      echo "Processing item #$number"

      # Simulate work
      sleep 1

      echo "Completed item #$number"
    ' _ {}
}

# Usage
issues=$(gh issue list --state open --json number,title --limit 50)
process_batch "$issues" 5
```

### Stream Processing
```bash
#!/bin/bash
# stream-process.sh - Process large datasets efficiently

process_stream() {
  local repo="$1"

  # Stream processing to avoid loading everything into memory
  gh issue list --repo "$repo" --state all --paginate --json number,title | \
    jq -c '.[]' | \
    while read -r issue; do
      number=$(echo "$issue" | jq -r '.number')
      title=$(echo "$issue" | jq -r '.title')

      # Process each issue
      if echo "$title" | grep -qi "bug"; then
        echo "Found bug: #$number - $title"
      fi
    done
}

# Usage
process_stream "owner/repo"
```

## Configuration Management

### Environment-Based Configuration
```bash
#!/bin/bash
# config.sh - Configuration management

# Load configuration from file or environment
load_config() {
  local config_file="${1:-config.env}"

  if [ -f "$config_file" ]; then
    # shellcheck source=/dev/null
    source "$config_file"
  fi

  # Environment variables with defaults
  export REPO="${REPO:-}"
  export GH_TOKEN="${GH_TOKEN:-}"
  export LOG_LEVEL="${LOG_LEVEL:-INFO}"
  export BATCH_SIZE="${BATCH_SIZE:-10}"
  export TIMEOUT="${TIMEOUT:-30}"
}

# Validate configuration
validate_config() {
  local required_vars=("REPO" "GH_TOKEN")

  for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      log_error "Required configuration variable $var is not set"
      exit 1
    fi
  done
}

# Usage
load_config "$@"
validate_config
```

### Dynamic Configuration
```bash
#!/bin/bash
# dynamic-config.sh - Runtime configuration

# Get configuration from repository
load_repo_config() {
  local repo="$1"
  local config_path="${2:-.github/config.json}"

  if ! config=$(gh api "repos/$repo/contents/$config_path" --jq '.content' | base64 -d 2>/dev/null); then
    log_warn "Could not load config from $repo:$config_path"
    return 1
  fi

  echo "$config"
}

# Apply configuration
apply_config() {
  local config="$1"

  # Extract settings
  batch_size=$(echo "$config" | jq -r '.batch_size // 10')
  timeout=$(echo "$config" | jq -r '.timeout // 30')

  export BATCH_SIZE="$batch_size"
  export TIMEOUT="$timeout"

  log_info "Applied configuration: batch_size=$batch_size, timeout=$timeout"
}

# Usage
config=$(load_repo_config "owner/repo" ".github/automation.json")
if [ -n "$config" ]; then
  apply_config "$config"
fi
```

## Progress Tracking

### Progress Bars
```bash
#!/bin/bash
# progress.sh - Show progress for long-running operations

show_progress() {
  local current="$1"
  local total="$2"
  local width="${3:-50}"

  if [ "$total" -eq 0 ]; then
    return
  fi

  local percentage=$((current * 100 / total))
  local completed=$((current * width / total))

  printf "\rProgress: [%-${width}s] %d%% (%d/%d)" \
    "$(printf '%.0s#' $(seq 1 $completed))" \
    "$percentage" "$current" "$total"
}

# Usage
total_items=$(gh issue list --state open --json number --jq length)
current=0

gh issue list --state open --json number --jq '.[]' | \
  while read -r item; do
    # Process item
    sleep 0.1

    current=$((current + 1))
    show_progress "$current" "$total_items"
  done

echo  # New line after progress bar
```

### Status Reporting
```bash
#!/bin/bash
# status-report.sh - Generate status reports

generate_report() {
  local repo="$1"
  local output_file="${2:-report.json}"

  log_info "Generating status report for $repo"

  # Collect various metrics
  repo_info=$(gh repo view "$repo" --json name,stargazersCount,forksCount,updatedAt)
  open_issues=$(gh issue list --repo "$repo" --state open --json number --jq length)
  open_prs=$(gh pr list --repo "$repo" --state open --json number --jq length)
  recent_commits=$(gh api "repos/$repo/commits?since=$(date -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)" --jq length)

  # Create report
  report=$(jq -n \
    --argjson repo_info "$repo_info" \
    --argjson open_issues "$open_issues" \
    --argjson open_prs "$open_prs" \
    --argjson recent_commits "$recent_commits" \
    '{
      repository: $repo_info,
      metrics: {
        open_issues: $open_issues,
        open_prs: $open_prs,
        recent_commits: $recent_commits,
        generated_at: now | strftime("%Y-%m-%dT%H:%M:%SZ")
      }
    }')

  echo "$report" > "$output_file"
  log_info "Report saved to $output_file"
}

# Usage
generate_report "owner/repo" "status-$(date +%Y%m%d).json"
```

## Scheduling Patterns

### Cron-Based Automation
```bash
#!/bin/bash
# cron-automation.sh - Scheduled automation tasks

# Daily repository health check
daily_health_check() {
  local repo="$1"

  log_info "Running daily health check for $repo"

  # Check for stale issues
  stale_count=$(gh issue list --repo "$repo" --state open \
    --search "updated:<$(date -d '30 days ago' +%Y-%m-%d)" \
    --json number --jq length)

  if [ "$stale_count" -gt 5 ]; then
    gh issue create --repo "$repo" \
      --title "🏥 Health Check: $stale_count stale issues detected" \
      --body "Found $stale_count issues not updated in the last 30 days." \
      --labels "maintenance"
  fi
}

# Weekly cleanup
weekly_cleanup() {
  local repo="$1"

  log_info "Running weekly cleanup for $repo"

  # Archive old closed issues
  gh issue list --repo "$repo" --state closed \
    --updated-before "$(date -d '90 days ago' +%Y-%m-%d)" \
    --limit 50 --json number --jq '.[].number' | \
    xargs -I {} gh issue edit {} --repo "$repo" --add-label "archived"
}

# Main execution based on day
main() {
  local repo="$1"

  case "$(date +%u)" in  # Day of week (1=Monday)
    1) # Monday - weekly cleanup
      weekly_cleanup "$repo"
      ;&
    *) # Every day - health check
      daily_health_check "$repo"
      ;;
  esac
}

# Usage (intended to be called by cron)
main "owner/repo"
```

### Event-Driven Automation
```bash
#!/bin/bash
# event-driven.sh - Respond to GitHub events

# Process webhook payload (when called by webhook)
process_webhook() {
  local event_type="$1"
  local payload_file="$2"

  case "$event_type" in
    "pull_request")
      process_pr_event "$payload_file"
      ;;
    "issues")
      process_issue_event "$payload_file"
      ;;
    "push")
      process_push_event "$payload_file"
      ;;
    *)
      log_info "Ignoring event type: $event_type"
      ;;
  esac
}

process_pr_event() {
  local payload_file="$1"

  action=$(jq -r '.action' "$payload_file")
  pr_number=$(jq -r '.pull_request.number' "$payload_file")
  repo=$(jq -r '.repository.full_name' "$payload_file")

  case "$action" in
    "opened")
      # Auto-assign reviewers
      gh pr edit "$pr_number" --repo "$repo" --add-reviewer "team/maintainers"
      ;;
    "closed")
      if jq -r '.pull_request.merged' "$payload_file" | grep -q true; then
        log_info "PR #$pr_number was merged"
        # Trigger deployment or other actions
      fi
      ;;
  esac
}

# Usage (called by webhook handler)
# process_webhook "$EVENT_TYPE" "$PAYLOAD_FILE"
```

## Performance Optimization

### Parallel Processing
```bash
#!/bin/bash
# parallel.sh - Parallel execution for better performance

process_repositories() {
  local repos_file="$1"
  local max_parallel="${2:-5}"

  # Process repositories in parallel
  cat "$repos_file" | \
    xargs -n 1 -P "$max_parallel" -I {} sh -c '
      repo="$1"
      echo "Processing $repo"

      # Repository-specific processing
      info=$(gh repo view "$repo" --json name,stargazersCount 2>/dev/null || echo "{}")

      # Output results (will be interleaved)
      echo "$repo: $(echo "$info" | jq -r ".stargazersCount // 0") stars"
    ' _ {}
}

# Usage
process_repositories "repositories.txt" 10
```

### Caching Strategies
```bash
#!/bin/bash
# caching.sh - Cache expensive operations

CACHE_DIR="${CACHE_DIR:-/tmp/gh-cache}"
CACHE_TTL="${CACHE_TTL:-3600}"  # 1 hour

# Create cache directory
mkdir -p "$CACHE_DIR"

# Cache key generator
cache_key() {
  echo "$*" | md5sum | cut -d' ' -f1
}

# Cached command execution
cached_exec() {
  local key=$(cache_key "$@")
  local cache_file="$CACHE_DIR/$key"

  # Check if cache is valid
  if [ -f "$cache_file" ] && [ $(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file") )) -lt "$CACHE_TTL" ]; then
    cat "$cache_file"
    return 0
  fi

  # Execute command and cache result
  "$@" | tee "$cache_file"
}

# Usage
# cached_exec gh repo list owner --json name
```

## Monitoring & Alerting

### Health Monitoring
```bash
#!/bin/bash
# monitor.sh - Monitor automation health

# Track success/failure rates
METRICS_FILE="${METRICS_FILE:-metrics.json}"

update_metrics() {
  local operation="$1"
  local success="${2:-1}"

  # Initialize metrics file if it doesn't exist
  if [ ! -f "$METRICS_FILE" ]; then
    echo '{"operations": {}}' > "$METRICS_FILE"
  fi

  # Update metrics
  jq --arg op "$operation" --argjson success "$success" '
    .operations[$op] |= (if . then
      .total += 1 |
      .success += $success |
      .failure += (1 - $success)
    else
      {total: 1, success: $success, failure: (1 - $success)}
    end)
  ' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
}

# Alert on failures
alert_on_failure() {
  local operation="$1"
  local threshold="${2:-0.8}"  # 80% success rate

  success_rate=$(jq -r ".operations[\"$operation\"] | (.success / .total)" "$METRICS_FILE" 2>/dev/null || echo "1")

  if (( $(echo "$success_rate < $threshold" | bc -l) )); then
    log_error "Operation '$operation' success rate below threshold: $success_rate"

    # Send alert (integrate with your alerting system)
    # curl -X POST -H 'Content-type: application/json' \
    #   --data '{"text": "Low success rate for '"$operation"'"}' \
    #   "$WEBHOOK_URL"
  fi
}

# Usage
if some_command; then
  update_metrics "some_operation" 1
else
  update_metrics "some_operation" 0
  alert_on_failure "some_operation"
fi
```

### Log Aggregation
```bash
#!/bin/bash
# logging.sh - Centralized logging

LOG_FILE="${LOG_FILE:-automation.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Logging levels
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Check if level should be logged
  if [ "${LOG_LEVELS[$level]}" -ge "${LOG_LEVELS[$LOG_LEVEL]}" ]; then
    echo "$timestamp [$level] $message" >> "$LOG_FILE"
    echo "$timestamp [$level] $message" >&2
  fi
}

# Convenience functions
debug() { log DEBUG "$@"; }
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
error() { log ERROR "$@"; }

# Usage
info "Starting automation script"
debug "Configuration loaded: REPO=$REPO"
warn "Rate limit approaching"
error "Authentication failed"
```