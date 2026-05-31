---
name: blastum-workspace-context
description: Organize workspace context files in tmp/ subfolders. Use when saving plans, results, notes, or docs.
---
# Workspace Context

Organize context files in `tmp/` with subfolders: `plans/`, `results/`, `notes/`, `docs/`.

## Structure

```
tmp/
  plans/    - project plans, task lists, roadmaps
  results/  - outputs, reports, analysis results
  notes/    - meeting notes, observations, ideas
  docs/     - documentation, references, guides
```

## Usage

When user requests to save/create:
- **Plan** → `tmp/plans/`
- **Result** → `tmp/results/`
- **Note** → `tmp/notes/`
- **Doc** → `tmp/docs/`

Create subfolders if missing. Use descriptive filenames with `.md` extension unless specified otherwise.
