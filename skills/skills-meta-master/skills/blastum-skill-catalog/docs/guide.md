# Skill Catalog Guide

## Overview

This skill generates a `skill-catalog.md` file in the project's `tmp/` folder containing all available skills sorted alphabetically in a markdown table with names and one-to-two sentence descriptions.

## Usage

The skill will:
1. Scan skills from `~/.cursor/skills` only (exclude `~/.codex` and `skills-cursor`)
2. Extract skill names and descriptions from their SKILL.md frontmatter
3. Sort skills alphabetically by name
4. Generate a markdown table
5. Save it to `tmp/skill-catalog.md` in the current project

## Output Format

```markdown
# Skill Catalog

| Skill | Description |
|-------|-------------|
| **ansible** | Infrastructure automation with Ansible. Use for server provisioning... |
| **conversation-notes** | Save a note summarizing what was learned in the current conversation. |
```

## Implementation Steps

1. Use the available skills API to get all skills
2. Parse frontmatter from each SKILL.md file
3. Extract name and description fields
4. Sort alphabetically by skill name
5. Generate markdown table
6. Write to tmp/skill-catalog.md