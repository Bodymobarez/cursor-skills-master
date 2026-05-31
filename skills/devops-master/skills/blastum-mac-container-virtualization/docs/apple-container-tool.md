# Apple's Container Tool Setup Guide

## Overview

Apple's container tool provides native container support for macOS, optimized for Apple Silicon with significantly lower resource usage than Docker Desktop.

## Installation & Setup

### Homebrew Installation

```bash
# Install Apple's container tool
brew install container

# Verify installation
container version
```

### System Initialization

```bash
# Start the container system
container system start

# Set recommended kernel for Apple Silicon
container system kernel set --recommended

# Verify system status
container system status
```

### Kernel Configuration

**For Apple Silicon (M1/M2/M3):**
```bash
container system kernel set --recommended
# Uses Kata Containers kernel optimized for ARM64
```

**For Intel Macs:**
```bash
container system kernel set --recommended
# Uses appropriate kernel for x86_64
```

## Core Concepts

### Architecture Difference

**Traditional Containers (Docker):**
```
macOS → Linux VM → Docker Engine → Shared Kernel → Containers
```

**Apple's Container Tool:**
```
macOS → Virtualization.framework → Kata Containers → Micro-VMs per Container
```

### Key Advantages

- **Micro-VMs**: Each container gets its own tiny VM
- **Isolation**: Better security than shared kernel
- **Performance**: Native Apple Silicon optimization
- **Resources**: ~50-100MB vs 1.5GB+ for Docker Desktop

## Basic Usage

### Building Images

```bash
# Navigate to project
cd swift-vapor-server

# Build from Containerfile
container build -t swift-vapor-server .

# Build with custom options
container build \
  --no-cache \
  --progress=plain \
  -t swift-vapor-server:v1.0 \
  .
```

### Running Containers

```bash
# Run in foreground (for development)
container run -it --rm -p 8080:8080 swift-vapor-server

# Run in background
container run -d -p 8080:8080 --name vapor-server swift-vapor-server

# Run with environment variables
container run -d -p 8080:8080 \
  -e PORT=8080 \
  -e LOG_LEVEL=debug \
  swift-vapor-server
```

### Container Management

```bash
# List running containers
container list

# View container logs
container logs vapor-server
container logs -f vapor-server  # Follow logs

# Execute commands in running container
container exec -it vapor-server bash

# Stop container
container stop vapor-server

# Remove container
container rm vapor-server
```

## Image Management

### Building Images

```bash
# Build with multiple tags
container build -t swift-vapor-server:latest -t swift-vapor-server:v1.0 .

# Build from different Containerfile
container build -f Containerfile.dev -t swift-vapor-server:dev .

# Build with build arguments
container build \
  --build-arg SWIFT_VERSION=6.2 \
  --build-arg UBUNTU_VERSION=noble \
  -t swift-vapor-server .
```

### Image Operations

```bash
# List images
container image list

# Inspect image details
container image inspect swift-vapor-server

# Remove image
container image rm swift-vapor-server

# Clean up unused images
container image prune
```

## Networking with Tailscale

### Host-Based Networking (Recommended)

```bash
# 1. Install Tailscale on macOS host
brew install tailscale
sudo brew services start tailscale
tailscale up --auth-key=tskey-...

# 2. Run container with port mapping
container run -d -p 8080:8080 \
  --name vapor-server \
  swift-vapor-server

# 3. Access via Tailscale
curl http://swift-vapor-server:8080/health
```

### Container Networking Details

**Port Mapping:**
```bash
# Map container port 8080 to host port 8080
container run -d -p 8080:8080 swift-vapor-server

# Map to different host port
container run -d -p 9000:8080 swift-vapor-server

# Map multiple ports
container run -d \
  -p 8080:8080 \
  -p 8081:8081 \
  swift-vapor-server
```

**Network Inspection:**
```bash
# Check port mappings
container port vapor-server

# View network configuration
container inspect vapor-server | jq .NetworkSettings
```

## Storage & Volumes

### Volume Management

```bash
# Create named volume
container volume create my-data

# Run with volume mount
container run -d \
  -v my-data:/app/data \
  -p 8080:8080 \
  swift-vapor-server

# List volumes
container volume list

# Remove volume
container volume rm my-data
```

### Bind Mounts

```bash
# Mount host directory
container run -d \
  -v $HOME/data:/app/data \
  -p 8080:8080 \
  swift-vapor-server

# Read-only mount
container run -d \
  -v $HOME/config:/app/config:ro \
  -p 8080:8080 \
  swift-vapor-server
```

## Development Workflow

### Development Setup

```bash
# Build development image
container build -f Containerfile.dev -t swift-vapor-server:dev .

# Run with source mounting
container run -d \
  -p 8080:8080 \
  -v $(pwd):/app \
  --name vapor-dev \
  swift-vapor-server:dev

# Live reload (if configured)
container logs -f vapor-dev
```

### Debugging Containers

```bash
# Access container shell
container exec -it vapor-server bash

# View container processes
container exec vapor-server ps aux

# Check network connections
container exec vapor-server netstat -tlnp

# Inspect environment
container exec vapor-server env
```

## System Management

### System Operations

```bash
# Check system status
container system status

# View system logs
container system logs
container system logs -f  # Follow logs

# Restart system
container system restart

# Stop system
container system stop
```

### Kernel Management

```bash
# List available kernels
container system kernel list

# Set specific kernel
container system kernel set kata

# Check current kernel
container system kernel current
```

## Performance Optimization

### Resource Usage Comparison

| Runtime | Memory Usage | Startup Time | CPU Overhead |
|---------|-------------|--------------|--------------|
| **Apple Container** | 50-100MB | 1-2s | Minimal |
| **Colima** | 150-200MB | 5-15s | Low |
| **OrbStack** | 100-150MB | 2-3s | Low |
| **Docker Desktop** | 1.5-2GB | 30+s | High |

### Optimization Tips

**For Development:**
```bash
# Use lightweight base images
FROM swift:6.2-slim AS build
FROM ubuntu:noble AS runtime

# Minimize installed packages
RUN apt-get install -y --no-install-recommends \
    libjemalloc2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

**For Production:**
```bash
# Use multi-stage builds
# Enable static linking
# Run as non-root user
# Add health checks
```

## Troubleshooting

### Common Issues

#### "apiserver is not running"

**Symptoms:**
```
Error: apiserver is not running
```

**Solutions:**
```bash
# Start the container system
container system start

# Check status
container system status

# Restart if needed
container system restart
```

#### "kernel not configured"

**Symptoms:**
```
Error: kernel not configured
```

**Solutions:**
```bash
# Set recommended kernel
container system kernel set --recommended

# List available kernels
container system kernel list

# Set specific kernel
container system kernel set kata
```

#### Build Failures

**Symptoms:**
```
Error: build failed
```

**Debug Steps:**
```bash
# Build with verbose output
container build --progress=plain -t test .

# Check build logs
container system logs | grep build

# Test in interactive container
container run -it --rm swift:6.2 bash
```

#### Port Conflicts

**Symptoms:**
```
Error: port already in use
```

**Solutions:**
```bash
# Find process using port
lsof -i :8080

# Use different port
container run -d -p 8081:8080 swift-vapor-server

# Kill conflicting process
kill -9 $(lsof -ti :8080)
```

### Network Issues

#### Container can't access network

```bash
# Check container networking
container exec vapor-server ping 8.8.8.8

# Restart container system
container system restart

# Check system logs
container system logs
```

#### Tailscale connectivity issues

```bash
# Verify host Tailscale
tailscale status

# Test container networking
container exec vapor-server curl http://localhost:8080/health

# Check port mapping
container port vapor-server
```

### Storage Issues

#### Volume mount failures

```bash
# Check volume exists
container volume list

# Create volume if missing
container volume create my-volume

# Check permissions
ls -la /path/to/host/directory
```

### Performance Issues

#### Slow startup

```bash
# Check system resources
container system status

# Restart system
container system restart

# Check kernel performance
container system kernel current
```

#### High memory usage

```bash
# Monitor container memory
container stats vapor-server

# Check for memory leaks in app
container logs vapor-server

# Restart container
container restart vapor-server
```

## Migration from Docker

### Command Translation

| Docker | Apple Container |
|--------|----------------|
| `docker build` | `container build` |
| `docker run` | `container run` |
| `docker ps` | `container list` |
| `docker logs` | `container logs` |
| `docker exec` | `container exec` |
| `docker stop` | `container stop` |
| `docker rm` | `container rm` |

### Networking Changes

**Docker (host networking):**
```yaml
services:
  app:
    network_mode: host
```

**Apple Container (port mapping):**
```bash
container run -d -p 8080:8080 swift-vapor-server
```

### Tailscale Migration

**From Docker:**
```yaml
# Tailscale in container
environment:
  - TAILSCALE_AUTH_KEY=...
cap_add:
  - NET_ADMIN
devices:
  - /dev/net/tun
network_mode: host
```

**To Apple Container:**
```bash
# Tailscale on host
tailscale up --auth-key=...

# Container with port mapping
container run -d -p 8080:8080 swift-vapor-server
```

## Advanced Configuration

### Custom Kernel Settings

```bash
# Advanced kernel configuration
container system kernel set \
  --kernel kata \
  --kernel-args "console=ttyS0 panic=1"

# Custom kernel image
container system kernel set \
  --kernel /path/to/custom/kernel
```

### System Configuration

```bash
# Configure system settings
container system config \
  --max-containers 10 \
  --max-images 100 \
  --storage-driver overlay2
```

### Integration with Xcode

```bash
# Build iOS apps in containers
container run -it \
  -v /Applications/Xcode.app:/Applications/Xcode.app \
  -e DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift:latest
```

## Best Practices

### Development

1. **Use descriptive names** for containers and images
2. **Clean up regularly** with `container system prune`
3. **Use volumes for data persistence**
4. **Monitor resource usage** with `container stats`

### Production

1. **Use specific image tags** (not `latest`)
2. **Implement health checks** in Containerfile
3. **Run as non-root user** for security
4. **Configure resource limits** appropriately
5. **Enable logging** and monitoring

### Security

1. **Keep system updated** with `brew upgrade container`
2. **Use trusted base images** only
3. **Scan images** for vulnerabilities
4. **Limit container privileges** appropriately
5. **Regular security audits** of running containers

## Resources

- [Apple Container Documentation](https://developer.apple.com/documentation/virtualization)
- [Kata Containers](https://katacontainers.io/)
- [OCI Image Specification](https://github.com/opencontainers/image-spec)
- [Swift Container Best Practices](https://github.com/swift-server/guides)