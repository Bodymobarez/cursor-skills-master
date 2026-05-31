# Migration from Docker to Apple's Container Tool

## Overview

This guide covers migrating from Docker Desktop, Colima, or other container runtimes to Apple's native container tool on macOS.

## Why Migrate to Apple's Container Tool?

- **Performance**: 50-100MB memory usage vs 1.5GB+ for Docker Desktop
- **Native Integration**: Built by Apple for optimal macOS performance
- **Micro-VM Architecture**: Better isolation with per-container VMs
- **Apple Silicon Optimized**: Native ARM64 performance
- **Security**: Hardware-based isolation with minimal attack surface

## Migration Checklist

- [ ] Backup existing containers and data
- [ ] Update Containerfile/Dockerfile syntax
- [ ] Change networking from host mode to port mapping
- [ ] Move Tailscale from container to host
- [ ] Update build and run scripts
- [ ] Test application functionality
- [ ] Update CI/CD pipelines if applicable

## Command Translation

### Basic Operations

| Docker | Apple Container |
|--------|----------------|
| `docker build -t app .` | `container build -t app .` |
| `docker run -d -p 8080:8080 app` | `container run -d -p 8080:8080 app` |
| `docker ps` | `container list` |
| `docker logs app` | `container logs app` |
| `docker stop app` | `container stop app` |
| `docker rm app` | `container rm app` |
| `docker images` | `container image list` |
| `docker rmi app` | `container image rm app` |

### Advanced Operations

| Docker | Apple Container |
|--------|----------------|
| `docker exec -it app bash` | `container exec -it app bash` |
| `docker volume ls` | `container volume list` |
| `docker network ls` | `container system status` |
| `docker system prune` | `container system prune` |
| `docker stats` | `container stats` |

## Networking Changes

### Host Networking (Docker)
```yaml
# docker-compose.yml
services:
  app:
    image: swift-vapor-server
    network_mode: host
    environment:
      - TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
```

**Problems:**
- Requires privileged access
- Complex TUN device management
- macOS compatibility issues
- Security concerns

### Port Mapping (Apple Container)
```bash
# Run command
container run -d -p 8080:8080 swift-vapor-server
```

**Benefits:**
- Standard networking
- Better isolation
- macOS compatible
- Tailscale runs on host

## Tailscale Migration

### Before: Tailscale in Container
```yaml
services:
  app:
    network_mode: host
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - tailscale-data:/var/lib/tailscale
```

### After: Tailscale on Host
```bash
# Install Tailscale on macOS
brew install tailscale
sudo brew services start tailscale
tailscale up --auth-key=tskey-...

# Run container normally
container run -d -p 8080:8080 swift-vapor-server
```

**Benefits:**
- Simpler container setup
- Better macOS integration
- More reliable networking
- Easier debugging

## Containerfile Updates

### Common Changes

**Remove privileged settings:**
```dockerfile
# Remove these from Containerfile
# USER root
# RUN apt-get install -y privileged-package
# USER vapor
```

**Update base images:**
```dockerfile
# Prefer Ubuntu noble for Apple Container
FROM ubuntu:noble
# Instead of FROM ubuntu:20.04
```

**Health checks remain the same:**
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1
```

## Build Process Changes

### Build Arguments
```bash
# Docker
docker build --build-arg SWIFT_VERSION=6.2 -t app .

# Apple Container (same syntax)
container build --build-arg SWIFT_VERSION=6.2 -t app .
```

### Multi-stage Builds
```dockerfile
# Same syntax works
FROM swift:6.2 AS build
# ... build steps ...

FROM ubuntu:noble AS runtime
# ... runtime setup ...

FROM runtime
# ... final image ...
```

## Volume Management

### Named Volumes
```bash
# Docker
docker volume create mydata
docker run -d -v mydata:/app/data app

# Apple Container
container volume create mydata
container run -d -v mydata:/app/data app
```

### Bind Mounts
```bash
# Same syntax works
container run -d -v $HOME/data:/app/data app
container run -d -v $(pwd):/app app
```

## Environment Variables

### Same Syntax
```bash
# Works identically
container run -d \
  -e PORT=8080 \
  -e LOG_LEVEL=debug \
  -e DATABASE_URL=postgres://... \
  app
```

### Environment Files
```bash
# Same syntax
container run -d --env-file .env app
```

## Development Workflow

### Local Development
```bash
# Instead of docker-compose
container run -d \
  -p 8080:8080 \
  -v $(pwd):/app \
  --name dev-app \
  swift-vapor-server

# View logs
container logs -f dev-app

# Debug
container exec -it dev-app bash
```

### Hot Reload
```bash
# Mount source code
container run -d \
  -p 8080:8080 \
  -v $(pwd)/Sources:/app/Sources \
  -v $(pwd)/Public:/app/Public \
  swift-vapor-server
```

## Production Deployment

### System Management
```bash
# Enable automatic startup
container system start

# Check status
container system status

# View logs
container system logs
```

### Resource Limits
```bash
# Set memory and CPU limits
container run -d \
  --memory 512m \
  --cpus 1.0 \
  --restart unless-stopped \
  -p 8080:8080 \
  app
```

### Monitoring
```bash
# Monitor containers
container stats

# Check health
container inspect app | jq .State.Health.Status

# System monitoring
container system status
```

## Troubleshooting Migration

### Build Failures
```bash
# Check build logs
container build -t debug-app . 2>&1 | tee build.log

# Test in clean environment
container system restart
container build -t app .
```

### Runtime Issues
```bash
# Check container status
container list

# View detailed logs
container logs app

# Inspect container
container inspect app

# Test networking
container exec app curl http://localhost:8080/health
```

### Performance Issues
```bash
# Compare resource usage
container stats app

# Check system resources
container system status

# Monitor over time
container stats --no-stream
```

## CI/CD Updates

### GitHub Actions Example
```yaml
# Before (Docker)
- name: Build and test
  run: |
    docker build -t app .
    docker run -d -p 8080:8080 app
    docker exec app swift test

# After (Apple Container)
- name: Build and test
  run: |
    container build -t app .
    container run -d -p 8080:8080 app
    container exec app swift test
```

### Script Updates
```bash
# Update deployment scripts
# FROM: docker-compose up -d
# TO: container run -d -p 8080:8080 app

# Update build scripts
# FROM: docker build -t app .
# TO: container build -t app .
```

## Common Migration Issues

### TUN Device Access
**Problem:** Tailscale requires TUN device in Docker
**Solution:** Run Tailscale on macOS host instead

### Host Networking
**Problem:** `network_mode: host` not available
**Solution:** Use port mapping with host-based Tailscale

### Privileged Containers
**Problem:** Security policies prevent privileged mode
**Solution:** Use standard containers with host networking

### Volume Permissions
**Problem:** File permission differences
**Solution:** Ensure proper user mapping in containers

### Build Context Size
**Problem:** Larger build contexts with Apple Silicon
**Solution:** Use `.containerignore` to exclude unnecessary files

## Performance Comparison

### Memory Usage
- **Docker Desktop**: 1.5-2GB baseline
- **Apple Container**: ~230MB per container
- **Improvement**: 85-90% memory reduction

### Startup Time
- **Docker Desktop**: 30-60 seconds
- **Apple Container**: 1-2 seconds
- **Improvement**: 30-60x faster startup

### CPU Usage
- **Docker Desktop**: 1-2% idle overhead
- **Apple Container**: 0.1-0.5% idle overhead
- **Improvement**: 75-95% CPU reduction

## Rollback Strategy

### Keep Docker Available
```bash
# Install Docker alongside Apple Container
brew install --cask docker

# Test Apple Container first
container run -d -p 8080:8080 test-app

# Rollback if needed
container stop test-app
docker run -d --network host test-app
```

### Hybrid Approach
```bash
# Use Apple Container for development
container run -d -p 8080:8080 dev-app

# Use Docker for complex networking
docker run -d --network host prod-app
```

## Best Practices

### Development
1. **Test builds locally** before CI/CD changes
2. **Use consistent tagging** across environments
3. **Document resource requirements** for containers
4. **Monitor performance metrics** during migration

### Production
1. **Implement health checks** in all containers
2. **Set resource limits** appropriately
3. **Use restart policies** for resilience
4. **Monitor logs and metrics** continuously

### Security
1. **Run as non-root user** in containers
2. **Use minimal base images** for smaller attack surface
3. **Regular security updates** for container images
4. **Network segmentation** with Tailscale ACLs

## Success Metrics

### Performance Metrics
- Container startup time < 5 seconds
- Memory usage < 300MB per container
- CPU overhead < 1% at idle

### Reliability Metrics
- Zero container crashes in production
- Successful health checks 100% of the time
- Fast recovery from failures

### Developer Experience
- Build time < 2 minutes for typical applications
- Easy debugging with exec access
- Consistent behavior across development environments

## Resources

- Apple Container Tool Documentation
- Containerfile Best Practices
- Troubleshooting Guide
- Command Reference