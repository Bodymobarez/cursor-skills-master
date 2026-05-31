# Performance Optimization Guide

## Overview

Performance tuning strategies for Apple's container tool, focusing on memory usage, startup time, and runtime efficiency for Swift Vapor applications.

## System-Level Optimization

### Kernel Configuration

**Recommended kernel settings:**
```bash
# Use optimized kernel
container system kernel set --recommended

# Check current kernel
container system kernel current

# List available kernels
container system kernel list
```

### System Resource Monitoring

**Monitor system performance:**
```bash
# Container resource usage
container stats

# System resource usage
top -l 1

# Memory pressure
vm_stat
```

## Container Optimization

### Resource Limits

**Memory and CPU constraints:**
```bash
container run -d \
  --memory 512m \
  --memory-swap 1g \
  --cpus 1.0 \
  --cpu-shares 1024 \
  swift-vapor-server
```

**Performance benefits:**
- Prevents resource exhaustion
- Predictable performance
- Better system stability

### Startup Optimization

**Fast container startup:**
```bash
# Pre-pull images
container image pull swift:6.2
container image pull ubuntu:noble

# Use faster storage
container volume create --driver local fast-storage

# Optimize kernel
container system kernel set kata
```

## Swift Application Tuning

### Memory Management

**Jemalloc optimization:**
```swift
// Application memory tuning
import Foundation

// Jemalloc environment variables
setenv("MALLOC_CONF", "narenas:1,tcache:false", 1)

// Memory-efficient data structures
let efficientArray = ContiguousArray<Element>()
```

### Runtime Performance

**Swift runtime tuning:**
```bash
# Environment variables
container run -d \
  -e SWIFT_THREADING=cooperative \
  -e SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all \
  swift-vapor-server
```

**Compilation optimizations:**
```dockerfile
RUN swift build -c release \
    --static-swift-stdlib \
    -Xswiftc -Osize \
    -Xswiftc -whole-module-optimization \
    -Xlinker -ljemalloc
```

## Networking Performance

### Tailscale Optimization

**Network performance tuning:**
```bash
# Check Tailscale status
tailscale status

# Network latency test
tailscale ping swift-vapor-server

# DNS performance
time nslookup swift-vapor-server
```

### Container Networking

**Network optimization:**
```bash
# Port mapping efficiency
container run -d -p 8080:8080 swift-vapor-server

# Network interface tuning
container exec vapor-server sysctl net.core.somaxconn=1024
```

## Storage Performance

### Volume Optimization

**High-performance volumes:**
```bash
# Create optimized volume
container volume create \
  --driver local \
  --opt type=tmpfs \
  --opt device=tmpfs \
  --opt o=size=100m,uid=1000 \
  fast-volume
```

### File System Caching

**Build cache optimization:**
```dockerfile
# Use build mounts for caching
RUN --mount=type=cache,target=/build/.build \
    swift build -c release
```

## Monitoring & Profiling

### Performance Monitoring

**Container metrics:**
```bash
# Real-time monitoring
container stats --no-stream

# Historical performance
container logs vapor-server | grep -i "performance\|memory\|cpu"
```

### Application Profiling

**Swift performance profiling:**
```bash
# CPU profiling
container exec vapor-server \
  perf record -F 99 -p $(pidof SwiftVaporServer) -o perf.data

# Memory profiling
container exec vapor-server \
  valgrind --tool=massif --massif-out-file=massif.out \
  ./SwiftVaporServer
```

## Benchmarking

### Startup Time Benchmarking

**Measure container startup:**
```bash
# Cold start timing
time container run -d --rm swift-vapor-server

# Warm start timing
container run -d swift-vapor-server
time container restart swift-vapor-server
```

### Application Performance

**HTTP performance testing:**
```bash
# Load testing
ab -n 1000 -c 10 http://localhost:8080/health

# Concurrent connections
wrk -t4 -c100 -d30s http://localhost:8080/health
```

### Memory Usage Analysis

**Memory profiling:**
```bash
# Container memory usage
container stats vapor-server --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Application memory
container exec vapor-server ps aux --sort=-%mem | head -5
```

## Optimization Strategies

### Development Optimization

**Fast development cycles:**
```bash
# Development container
container build -f Containerfile.dev -t vapor-dev .

# Quick rebuilds
container run -d \
  --mount type=bind,source=$(pwd),target=/app \
  vapor-dev
```

### Production Optimization

**Production performance:**
```bash
# Optimized production build
container build \
  --target runtime \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  -t vapor-prod .

# Production deployment
container run -d \
  --memory 1g \
  --cpus 2.0 \
  --restart unless-stopped \
  vapor-prod
```

## Troubleshooting Performance

### Slow Startup

**Diagnose startup delays:**
```bash
# Time breakdown
time container run -d swift-vapor-server

# Check kernel performance
container system kernel current

# Monitor startup logs
container logs swift-vapor-server | head -20
```

### High Memory Usage

**Memory leak detection:**
```bash
# Container memory stats
container stats swift-vapor-server

# Application memory usage
container exec swift-vapor-server free -h

# Swift memory debugging
container run -d \
  -e SWIFT_BACKTRACE=enable=yes,sanitize=thread \
  swift-vapor-server
```

### CPU Performance Issues

**CPU optimization:**
```bash
# CPU usage monitoring
container stats swift-vapor-server --format "table {{.CPUPerc}}"

# Threading analysis
container exec swift-vapor-server ps -T -p $(pidof SwiftVaporServer)
```

## Best Practices

### Resource Management
1. Set appropriate resource limits
2. Monitor resource usage continuously
3. Use performance profiling tools
4. Optimize for target workload

### Application Tuning
1. Use jemalloc for memory management
2. Enable Swift optimizations
3. Profile and optimize hot paths
4. Minimize allocations in performance-critical code

### System Optimization
1. Use recommended kernel settings
2. Optimize storage performance
3. Monitor system resources
4. Regular performance audits

### Development Workflow
1. Use development-optimized builds
2. Implement fast rebuild cycles
3. Profile during development
4. Test performance across scenarios

## Performance Targets

### Startup Time Goals
- Cold start: < 5 seconds
- Warm restart: < 1 second
- Development rebuild: < 30 seconds

### Memory Usage Goals
- Baseline: < 100MB per container
- Under load: < 300MB per container
- Memory growth: < 10% per hour

### CPU Usage Goals
- Idle: < 5% CPU usage
- Under load: < 70% CPU usage
- Efficient scaling with load

### Network Performance
- Latency: < 10ms local, < 50ms remote
- Throughput: > 100 Mbps
- Connection handling: > 1000 concurrent

## Related Topics

- Virtualization Architecture - System performance factors
- Swift Vapor Build Optimization - Build-time performance
- Deployment Strategies - Runtime optimization
- Troubleshooting Guide - Performance issue resolution