# File Change Tracker Guide

## Purpose

Mandates that every response which creates or modifies files must end with a bullet list of all changed files as clickable links.

## Implementation

### Always Active

This skill is always active. It applies to any response that involves file modifications.

### Format Requirement

At the very end of each response that changes files, provide:

```
## Files Changed
- [filename.ext](path/to/filename.ext)
- [another-file.md](path/to/another-file.md)
```

### Rules

1. **Only when files change**: Only include this section when files are actually modified
2. **All changed files**: List every file that was created, modified, or deleted
3. **Clickable links**: Use markdown link format with relative paths
4. **At the very end**: This section must be the final content in the response
5. **Consistent format**: Use "## Files Changed" as the header, followed by bullet list

### Examples

#### Valid Response Ending
```
Updated the configuration file with new settings.

## Files Changed
- [config.json](src/config.json)
- [README.md](README.md)
```

#### Invalid (missing section)
```
Updated the configuration file with new settings.
```

#### Invalid (wrong position)
```
## Files Changed
- [config.json](src/config.json)

Updated the configuration file with new settings.
```