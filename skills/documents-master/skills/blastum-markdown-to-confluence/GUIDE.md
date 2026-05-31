---
name: blastum-markdown-to-confluence
description: Upload markdown files directly to Confluence using REST API. Use when creating or updating Confluence pages from markdown documents.
---

# Markdown to Confluence Upload

Upload markdown files directly to Confluence using the Confluence REST API. The script uploads markdown as-is - Confluence handles the conversion automatically.

## Basic Usage

### Upload Markdown File

```bash
tmp/upload_markdown_to_confluence.sh "SPACE_KEY" "Page Title" "path/to/file.md"
```

**Parameters:**
- `SPACE_KEY`: Confluence space key (e.g., `ENG`, `DOCS`, or a personal space like `~7123456789abcdef01234567`)
- `Page Title`: Title for the Confluence page
- `path/to/file.md`: Path to your markdown file

### Examples

```bash
# Upload to a team space
tmp/upload_markdown_to_confluence.sh "ENG" "Architecture overview" "tmp/architecture.md"

# Upload to personal space
tmp/upload_markdown_to_confluence.sh "~7123456789abcdef01234567" "My Notes" "docs/notes.md"
```

## How It Works

1. **Reads markdown file** from the specified path
2. **Uploads markdown directly** via REST API using Confluence markdown representation format
3. **Confluence converts** the markdown to its internal format automatically
4. **Returns page URL** in the correct format: `https://your-site.atlassian.net/wiki/spaces/SPACE_KEY/pages/PAGE_ID/TITLE`

## Authentication

The script automatically retrieves your API token from macOS Keychain. Store your token with:

```bash
security add-generic-password -a "your-email@domain.com" -s "atlassian_api_token" -w "YOUR_API_TOKEN"
```

Or set it as an environment variable:
```bash
export CONFLUENCE_API_TOKEN="your_token"
tmp/upload_markdown_to_confluence.sh "SPACE_KEY" "Title" "file.md"
```

**Important:** Your API token must have Confluence read/write permissions. Create tokens at: https://id.atlassian.com/manage-profile/security/api-tokens

## Common Space Keys

Examples only — use keys from your own Confluence site:

- Team spaces: often short uppercase keys (e.g. `ENG`, `DOCS`)
- `~ACCOUNT_ID`: Personal space (Atlassian account id; find in space settings or URL)

## URL Format

Pages are created with URLs in the format:
```
https://your-site.atlassian.net/wiki/spaces/SPACE_KEY/pages/PAGE_ID/PAGE_TITLE
```

The script automatically constructs the correct URL with `/wiki/` prefix.

## Markdown Support

The script supports standard markdown features:
- Headings (`#`, `##`, `###`)
- Bold (`**text**`) and italic (`*text*`)
- Lists (ordered and unordered)
- Code blocks (```) and inline code (`)
- Links (`[text](url)`)
- Tables (markdown table syntax)
- Images (`![alt](url)`)

## Troubleshooting

### Authentication Issues
- Verify API token is stored in Keychain: `security find-generic-password -a "your-email" -s "atlassian_api_token" -w`
- Ensure token has Confluence permissions
- Check authentication: `acli confluence auth status`

### Permission Errors (403)
- Verify your API token has Confluence read/write permissions
- Create a new token with Confluence access if needed

### Page Not Found
- Verify space key is correct
- Check you have permissions in the space
- Ensure page title matches exactly (case-sensitive)

## Related Tools

- **Upload Script**: `tmp/upload_markdown_to_confluence.sh`
- **Confluence Integration Rule**: `.cursor/rules/confluence-integration.mdc`
- **Confluence Formatting Rule**: `.cursor/rules/confluence-formatting.mdc`
