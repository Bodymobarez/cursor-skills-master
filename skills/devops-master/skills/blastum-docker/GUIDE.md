---
name: blastum-docker
description: Dockerfile authoring, Docker Compose configuration, and containerization best practices. Use when creating Dockerfiles, optimizing builds, configuring Compose files, or implementing containerization patterns. For CLI commands, use docker-cli skill.
---
# Docker Skill

Dockerfile authoring, Compose configuration, and containerization best practices.

## Resources

- [Dockerfile Patterns](docs/dockerfile.md) - Best practices and language-specific examples
- [Compose Configuration](docs/compose.md) - Multi-container orchestration
- [Production Patterns](docs/production.md) - Deployment, security, CI/CD

**For CLI commands**: Use `docker-cli` skill.

## Core Concepts

**Containers**: Lightweight, isolated processes bundling applications with dependencies. Ephemeral by default.

**Images**: Layered read-only filesystems built from Dockerfiles. Immutable templates.

**Volumes**: Persistent storage surviving container lifecycle. Use named volumes for data.

**Networks**: Isolated network namespaces. Bridge (default), host, overlay (Swarm), MACVLAN.

## Quick Reference

**Base Images**: `node:20-alpine`, `python:3.11-slim`, `nginx:alpine`, `postgres:15-alpine`

**Multi-stage pattern**: Build stage → Production stage (removes build tools)

**Layer caching**: Copy dependencies before application code

**Security**: Non-root user, specific versions, minimal base images, vulnerability scanning
