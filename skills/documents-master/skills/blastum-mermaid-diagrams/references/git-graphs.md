# Git Graphs

Git graphs visualize version control branching strategies, commit history, and merge patterns.

## Basic Syntax

```mermaid
gitGraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Setup"
```

## Commits

### Simple Commits
```mermaid
gitGraph
    commit id: "Initial commit"
    commit id: "Add README"
    commit id: "Fix typo"
```

### Commits with Tags
```mermaid
gitGraph
    commit id: "Initial"
    commit id: "v1.0" tag: "v1.0"
    commit id: "Hotfix"
    commit id: "v1.1" tag: "v1.1"
```

## Branches

### Create and Checkout
```mermaid
gitGraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Feature A"
    commit id: "Feature B"
```

### Multiple Branches
```mermaid
gitGraph
    commit id: "Initial"
    branch feature/auth
    checkout feature/auth
    commit id: "Add login"
    commit id: "Add logout"
    checkout main
    branch feature/payment
    checkout feature/payment
    commit id: "Payment API"
```

## Merges

### Merge Branch
```mermaid
gitGraph
    commit id: "Initial"
    branch feature
    checkout feature
    commit id: "Feature work"
    checkout main
    merge feature
    commit id: "Merge complete"
```

### Merge with Tag
```mermaid
gitGraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Development work"
    checkout main
    merge develop tag: "v1.0"
```

## Common Branching Strategies

### Git Flow
```mermaid
gitGraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Setup"
    
    branch feature/auth
    checkout feature/auth
    commit id: "Add login"
    commit id: "Add logout"
    
    checkout develop
    merge feature/auth
    commit id: "Merge auth"
    
    branch release/v1.0
    checkout release/v1.0
    commit id: "Fix bugs"
    
    checkout main
    merge release/v1.0 tag: "v1.0"
    
    checkout develop
    merge release/v1.0
    
    branch hotfix/critical
    checkout hotfix/critical
    commit id: "Critical fix"
    
    checkout main
    merge hotfix/critical tag: "v1.0.1"
    
    checkout develop
    merge hotfix/critical
```

### GitHub Flow
```mermaid
gitGraph
    commit id: "Initial"
    branch feature/new-feature
    checkout feature/new-feature
    commit id: "Add feature"
    commit id: "Fix tests"
    checkout main
    merge feature/new-feature
    commit id: "Deploy"
```

### Trunk-Based Development
```mermaid
gitGraph
    commit id: "Initial"
    commit id: "Feature A"
    commit id: "Feature B"
    commit id: "Feature C"
    commit id: "Hotfix"
    commit id: "Feature D"
```

## Feature Branch Workflow

```mermaid
gitGraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Setup project"
    
    branch feature/user-auth
    checkout feature/user-auth
    commit id: "Add login form"
    commit id: "Add validation"
    commit id: "Add tests"
    
    checkout develop
    merge feature/user-auth
    commit id: "Merge user auth"
    
    branch feature/payment
    checkout feature/payment
    commit id: "Payment API"
    commit id: "Payment UI"
    
    checkout develop
    merge feature/payment
    commit id: "Merge payment"
    
    branch release/v1.0
    checkout release/v1.0
    commit id: "Fix critical bug"
    commit id: "Update docs"
    
    checkout main
    merge release/v1.0 tag: "v1.0.0"
    
    checkout develop
    merge release/v1.0
```

## Release Process

```mermaid
gitGraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Development"
    
    branch release/v1.0
    checkout release/v1.0
    commit id: "Prepare release"
    commit id: "Fix bugs"
    commit id: "Update version"
    
    checkout main
    merge release/v1.0 tag: "v1.0.0"
    
    checkout develop
    merge release/v1.0
    
    branch hotfix/security
    checkout hotfix/security
    commit id: "Security patch"
    
    checkout main
    merge hotfix/security tag: "v1.0.1"
    
    checkout develop
    merge hotfix/security
```

## Best Practices

1. **Clear commit messages** - Use descriptive IDs
2. **Show branch purpose** - Name branches meaningfully
3. **Show merge points** - Indicate when branches merge
4. **Tag releases** - Mark version tags
5. **Show flow** - Demonstrate branching strategy
6. **Keep it simple** - Don't overcrowd with too many branches

## Common Use Cases

- **Document branching strategy** - Show team workflow
- **Explain merge process** - Visualize how features integrate
- **Release planning** - Show release branches and tags
- **Onboarding** - Help new team members understand git flow
- **Code review** - Show where changes come from
