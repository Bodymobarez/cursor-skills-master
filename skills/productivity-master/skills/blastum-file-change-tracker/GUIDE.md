---
name: blastum-file-change-tracker
description: Mandates providing organized list of changed files grouped by folder as links at end of responses. Always active when files are modified.
---
# File Change Tracker

Ensures every response that modifies files ends with a bullet list of changed files as links, organized by folder.

## Implementation

When files are modified, group them by their containing folder and present them with folder headings:

```
## folder/path
- [file1.ext](folder/path/file1.ext)
- [file2.ext](folder/path/file2.ext)

## another/folder
- [file3.ext](another/folder/file3.ext)
```

Files in the root directory should be listed under "## /" or similar.

## Resources

- [Guide](docs/guide.md)