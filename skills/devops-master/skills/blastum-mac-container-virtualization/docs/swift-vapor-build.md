# Swift Vapor Build Optimization

## Overview

Optimization techniques for building Swift Vapor applications in Apple's container tool, focusing on build speed, image size, and performance.

## Multi-Stage Build Pattern

### Build Stage Optimization

**Separate compilation from runtime:**
```dockerfile
FROM swift:6.2 AS build

# Dependency caching
WORKDIR /build
COPY Package.* ./
RUN swift package resolve

# Source compilation
COPY . .
RUN swift build -c release \
    --static-swift-stdlib \
    -Xlinker -ljemalloc

# Runtime stage
FROM ubuntu:noble
COPY --from=build /build/.build/release/SwiftVaporServer .
```

**Benefits:**
- Smaller final image size
- Faster subsequent builds
- Cleaner separation of concerns

### Dependency Caching

**Cache package resolution:**
```dockerfile
# Copy dependency manifest first
COPY Package.swift Package.resolved ./

# Resolve dependencies (cached layer)
RUN swift package resolve \
    $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# Copy source after dependencies resolved
COPY Sources ./Sources
```

**Cache invalidation:**
- Only changes when Package.* files change
- Faster rebuilds for source-only changes

## Compilation Optimizations

### Release Build Flags

**Performance optimizations:**
```dockerfile
RUN swift build -c release \
    --static-swift-stdlib \
    -Xlinker -ljemalloc \
    -Xswiftc -Osize \
    -Xswiftc -whole-module-optimization
```

**Flag explanations:**
- `--static-swift-stdlib`: Static linking for smaller runtime
- `-Xlinker -ljemalloc`: High-performance memory allocator
- `-Osize`: Optimize for size
- `-whole-module-optimization`: Cross-file optimizations

### Cross-Compilation

**Apple Silicon optimization:**
```dockerfile
# Native ARM64 compilation
FROM --platform=linux/arm64 swift:6.2

# Ensure ARM64 target
ENV SWIFT_PLATFORM=linux-arm64
```

## Image Size Optimization

### Package Minimization

**Remove unnecessary packages:**
```dockerfile
FROM ubuntu:noble

RUN apt-get update && apt-get install -y \
    libjemalloc2 \
    ca-certificates \
    tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean
```

**Multi-stage cleanup:**
```dockerfile
# Remove build artifacts
RUN rm -rf /build/.build \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

### Layer Optimization

**Order instructions for caching:**
```dockerfile
# Rarely changing layers first
COPY Package.* ./
RUN swift package resolve

# Frequently changing layers last
COPY Sources ./Sources
RUN swift build -c release
```

## Performance Tuning

### Memory Allocation

**Jemalloc integration:**
```dockerfile
# Static linking in build
RUN swift build -c release -Xlinker -ljemalloc

# Runtime library in Ubuntu
RUN apt-get install -y libjemalloc2
```

**Performance benefits:**
- Better memory utilization
- Reduced allocation overhead
- Improved concurrent performance

### Startup Optimization

**Pre-compiled binaries:**
```dockerfile
# Static Swift runtime
RUN swift build --static-swift-stdlib

# Faster startup, smaller memory footprint
```

## Build Strategies

### Development Builds

**Fast iteration:**
```dockerfile
# Debug build for development
RUN swift build -c debug

# Include debug symbols
ENV SWIFT_BACKTRACE=enable=yes
```

### Production Builds

**Optimized for deployment:**
```dockerfile
# Release build with optimizations
RUN swift build -c release \
    --static-swift-stdlib \
    -Xswiftc -Osize

# Production environment
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes
```

## Cross-Platform Considerations

### Apple Silicon Specific

**Native performance:**
```bash
# Build on Apple Silicon for ARM64
container build --platform linux/arm64 -t app .
```

### Intel Mac Compatibility

**Rosetta translation:**
```bash
# Build for x86_64 on Intel Macs
container build --platform linux/amd64 -t app .
```

## Troubleshooting Builds

### Compilation Errors

**Swift version compatibility:**
```bash
# Check Swift version
swift --version

# Verify Package.swift compatibility
cat Package.swift | grep swift-tools-version
```

### Dependency Issues

**Package resolution failures:**
```dockerfile
# Force clean resolution
RUN rm -rf .build && swift package resolve

# Update package registry
RUN swift package update
```

### Build Performance

**Slow compilation:**
```dockerfile
# Use build cache
RUN --mount=type=cache,target=/build/.build \
    swift build -c release
```

## Best Practices

### Build Efficiency
1. Use multi-stage builds
2. Cache dependencies effectively
3. Minimize final image size
4. Optimize layer ordering

### Performance Focus
1. Use release builds for production
2. Enable static linking
3. Integrate jemalloc
4. Optimize for target platform

### Maintenance
1. Keep base images updated
2. Regular dependency updates
3. Monitor build performance
4. Document build requirements

## Related Topics

- Containerfile Structure - Build file anatomy
- Deployment Strategies - Runtime optimization
- Troubleshooting Guide - Build issue resolution