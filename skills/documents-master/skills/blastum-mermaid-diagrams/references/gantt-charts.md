# Gantt Charts

Gantt charts visualize project timelines, showing tasks, durations, dependencies, and milestones.

## Basic Syntax

```mermaid
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    section Phase 1
    Task 1 :a1, 2024-01-01, 30d
    Task 2 :a2, after a1, 20d
```

## Date Format

Specify date format:

```mermaid
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    section Phase 1
    Task :2024-01-01, 30d
```

**Common formats:**
- `YYYY-MM-DD` - 2024-01-15
- `MM/DD/YYYY` - 01/15/2024
- `DD-MM-YYYY` - 15-01-2024

## Task Definition

### Basic Task
```mermaid
gantt
    title Simple Project
    dateFormat YYYY-MM-DD
    section Development
    Design :2024-01-01, 10d
    Implementation :2024-01-11, 20d
    Testing :2024-01-31, 5d
```

### Task with ID
```mermaid
gantt
    title Project
    dateFormat YYYY-MM-DD
    section Phase 1
    Task 1 :a1, 2024-01-01, 30d
    Task 2 :a2, after a1, 20d
    Task 3 :a3, after a2, 10d
```

## Dependencies

### After Another Task
```mermaid
gantt
    title Project with Dependencies
    dateFormat YYYY-MM-DD
    section Phase 1
    Design :a1, 2024-01-01, 10d
    Development :a2, after a1, 20d
    Testing :a3, after a2, 5d
```

### Multiple Dependencies
```mermaid
gantt
    title Complex Project
    dateFormat YYYY-MM-DD
    section Phase 1
    Task A :a1, 2024-01-01, 10d
    Task B :a2, 2024-01-01, 15d
    Task C :a3, after a1 a2, 20d
```

## Task Status

Mark tasks with status:

```mermaid
gantt
    title Project Status
    dateFormat YYYY-MM-DD
    section Development
    Completed Task :done, a1, 2024-01-01, 10d
    Active Task :active, a2, 2024-01-11, 15d
    Future Task :a3, 2024-01-26, 10d
    Critical Task :crit, a4, 2024-01-11, 5d
    Milestone :milestone, m1, 2024-01-16, 0d
```

**Status types:**
- `done` - Completed task
- `active` - Currently in progress
- `crit` - Critical path task
- `milestone` - Milestone marker (0 duration)

## Milestones

Mark important dates:

```mermaid
gantt
    title Project with Milestones
    dateFormat YYYY-MM-DD
    section Phase 1
    Design :a1, 2024-01-01, 10d
    Milestone 1 :milestone, m1, 2024-01-11, 0d
    Development :a2, 2024-01-12, 20d
    Milestone 2 :milestone, m2, 2024-02-01, 0d
```

## Sections

Organize tasks into sections:

```mermaid
gantt
    title Multi-Phase Project
    dateFormat YYYY-MM-DD
    section Planning
    Requirements :a1, 2024-01-01, 10d
    Design :a2, after a1, 15d
    
    section Development
    Backend :a3, 2024-01-26, 20d
    Frontend :a4, 2024-01-26, 25d
    
    section Testing
    Unit Tests :a5, after a3, 10d
    Integration Tests :a6, after a4, 10d
    E2E Tests :a7, after a5 a6, 5d
```

## Comprehensive Example: Software Release

```mermaid
gantt
    title Software Release v2.0
    dateFormat YYYY-MM-DD
    
    section Planning
    Requirements Gathering :done, req, 2024-01-01, 10d
    Architecture Design :done, arch, after req, 15d
    Planning Complete :milestone, m1, 2024-01-26, 0d
    
    section Development
    Backend API :active, backend, 2024-01-27, 30d
    Frontend UI :frontend, 2024-01-27, 35d
    Database Schema :db, 2024-01-27, 20d
    
    section Integration
    API Integration :crit, api-int, after backend, 10d
    Frontend Integration :fe-int, after frontend api-int, 15d
    
    section Testing
    Unit Tests :unit, after backend, 15d
    Integration Tests :integration, after api-int, 10d
    E2E Tests :e2e, after fe-int, 7d
    Bug Fixes :bugs, after e2e, 10d
    
    section Release
    Documentation :docs, 2024-02-15, 20d
    Release Prep :prep, after bugs, 5d
    Release v2.0 :milestone, release, 2024-03-15, 0d
```

## Task Durations

Specify duration in different units:

```mermaid
gantt
    title Duration Examples
    dateFormat YYYY-MM-DD
    section Tasks
    Days :2024-01-01, 10d
    Weeks :2024-01-11, 2w
    Months :2024-01-25, 1M
```

**Duration units:**
- `d` - Days
- `w` - Weeks
- `M` - Months
- `y` - Years

## Best Practices

1. **Use sections** - Group related tasks
2. **Set dependencies** - Show task relationships
3. **Mark milestones** - Highlight key dates
4. **Use status** - Show progress (done, active)
5. **Critical path** - Mark critical tasks with `crit`
6. **Realistic durations** - Base on estimates, not wishes
7. **Update regularly** - Keep charts current

## Common Use Cases

- **Project Planning** - Visualize entire project timeline
- **Sprint Planning** - Show sprint tasks and dependencies
- **Release Planning** - Track release milestones
- **Resource Planning** - Show who works on what when
- **Feature Development** - Track feature from design to release
