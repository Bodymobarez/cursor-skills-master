# Swift Vapor Containerfile Structure

## Overview

This guide explains the Containerfile used for Swift Vapor server deployment, optimized for Apple's container runtime on macOS with Tailscale networking.

## Containerfile Architecture

### Multi-Stage Build Pattern

```
Build Stage (swift:6.2)
    ↓ Dependencies
    ↓ Compilation
    ↓ Static Linking
    ↓ Binary Creation
    ↓
Runtime Stage (ubuntu:noble)
    ↓ Minimal Runtime
    ↓ Security Hardening
    ↓ Health Checks
    ↓ Final Image
```

### Key Optimizations

- **Static Swift Linking**: Reduces runtime dependencies
- **Jemalloc**: High-performance memory allocator
- **Non-root User**: Security hardening
- **Minimal Base Image**: Smaller attack surface
- **Health Checks**: Container monitoring

## Detailed Build Stages

### Stage 1: Swift Build Environment

```dockerfile
FROM swift:6.2 AS build

# System dependencies for compilation
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y \
      libjemalloc-dev \
      curl \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

**Purpose**: Provides Swift compiler and build tools
**Size**: ~1.5GB (includes full Swift toolchain)
**Key packages**:
- `libjemalloc-dev`: Development headers for jemalloc
- `curl`: For health checks and networking
- `ca-certificates`: SSL certificate validation

### Dependency Resolution Caching

```dockerfile
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)
```

**Optimization**: Separate dependency resolution from compilation
**Benefit**: Faster rebuilds when only source code changes
**Cache Layer**: Docker layer cache preserves resolved dependencies

### Source Code Integration

```dockerfile
# Copy entire repo into container
COPY . .
```

**Includes**:
- Source code (`Sources/`)
- Tests (`Tests/`)
- Package manifest (`Package.swift`)
- Resources (`Public/`, `Resources/`)
- Startup script (`start.sh`)

### Compilation with Optimizations

```dockerfile
RUN --mount=type=cache,target=/build/.build \
    swift build -c release \
        --product SwiftVaporServer \
        --static-swift-stdlib \
        -Xlinker -ljemalloc && \
    # Copy main executable to staging area
    cp "$(swift build -c release --show-bin-path)/SwiftVaporServer" /staging && \
    # Copy resources bundled by SPM to staging area
    find -L "$(swift build -c release --show-bin-path)" -regex '.*\.resources$' -exec cp -Ra {} /staging \;
```

**Build Flags**:
- `-c release`: Optimized compilation
- `--static-swift-stdlib`: Static linking for smaller runtime
- `-Xlinker -ljemalloc`: Link with jemalloc for better memory performance

**Resource Handling**:
- SPM bundles resources into `.resources` directories
- Recursive copy preserves directory structure
- `-L` flag follows symlinks

### Stage 2: Runtime Environment

```dockerfile
FROM ubuntu:noble

# Minimal runtime packages
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      tzdata \
      curl \
    && rm -rf /var/lib/apt/lists/*
```

**Base Image**: Ubuntu 24.04 LTS (noble)
**Runtime Dependencies**:
- `libjemalloc2`: Runtime jemalloc library
- `ca-certificates`: SSL certificates for HTTPS
- `tzdata`: Timezone data
- `curl`: Health check command

### Security Hardening

```dockerfile
# Create a vapor user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

# Switch to the new home directory
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build --chown=vapor:vapor /staging /app

# Copy startup script
COPY --from=build --chown=vapor:vapor /build/start.sh ./start.sh
```

**Security Features**:
- Non-root user (`vapor:vapor`)
- Minimal privileges
- Dedicated application directory
- Proper file ownership

### Runtime Configuration

```dockerfile
# Swift crash reporting configuration
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

# Application configuration
ENV PORT=8080
ENV HOSTNAME=0.0.0.0

# Switch to vapor user
USER vapor:vapor
```

**Environment Variables**:
- `SWIFT_BACKTRACE`: Enhanced crash reporting
- `PORT`: Application port (configurable)
- `HOSTNAME`: Bind address (0.0.0.0 for all interfaces)

### Port Exposure and Health Checks

```dockerfile
# Expose port for networking
EXPOSE 8080

# Health check configuration
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Application entrypoint
ENTRYPOINT ["./start.sh"]
```

**Health Check Parameters**:
- `--interval=30s`: Check every 30 seconds
- `--timeout=3s`: Fail if check takes longer than 3 seconds
- `--start-period=5s`: Wait 5 seconds after startup before checking
- `--retries=3`: Allow 3 failures before marking unhealthy

## Build Process Deep Dive

### Layer Optimization

**Build Layer Caching**:
```
Layer 1: Base Swift image (cached)
Layer 2: System dependencies (cached)
Layer 3: Dependency resolution (cached if Package.* unchanged)
Layer 4: Source code copy (changes often)
Layer 5: Compilation (changes when source changes)
Layer 6: Runtime Ubuntu base (cached)
Layer 7: Runtime dependencies (cached)
Layer 8: User creation (cached)
Layer 9: Binary and resources copy (changes with build)
Layer 10: Startup script copy (rarely changes)
```

### Build Context

**What gets sent to Docker**:
```
swift-vapor-server/
├── Containerfile
├── Package.swift
├── Package.resolved
├── Sources/
├── Tests/
├── Public/
├── Resources/
└── start.sh
```

**Optimizations**:
- Use `.containerignore` to exclude unnecessary files
- Keep context small for faster builds
- Include only required source files

### Cross-Platform Considerations

**Apple Silicon (ARM64)**:
- Native Swift compilation
- Optimized for M1/M2/M3
- Faster builds than Intel emulation

**Intel Macs**:
- Rosetta translation for ARM64 containers
- May be slower but fully compatible

**Linux Deployment**:
- Same Containerfile works on Linux
- Can use Docker instead of Apple's container tool

## Runtime Behavior

### Startup Sequence

1. **Container starts** as `vapor` user
2. **ENTRYPOINT** executes `./start.sh`
3. **start.sh** launches Swift Vapor application
4. **Health check** begins monitoring `/health` endpoint
5. **Application** binds to `0.0.0.0:8080`

### Memory Management

**Jemalloc Integration**:
- Statically linked for better performance
- Reduces memory fragmentation
- Optimized for concurrent applications

**Swift Runtime**:
- Static linking reduces dynamic dependencies
- Faster startup times
- Smaller memory footprint

### Networking

**Container Networking**:
- Binds to all interfaces (`0.0.0.0`)
- Port 8080 exposed for external access
- Works with both localhost and Tailscale access

**Tailscale Integration**:
- No Tailscale daemon in container (host-based)
- Standard port mapping
- Hostname resolution via MagicDNS

## Customization Examples

### Adding Custom Dependencies

```dockerfile
# In build stage
RUN apt-get install -y \
    libssl-dev \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# In runtime stage
RUN apt-get install -y \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*
```

### Environment-Specific Builds

```dockerfile
# Development build
RUN swift build -c debug --product SwiftVaporServer

# Production build (current)
RUN swift build -c release --product SwiftVaporServer --static-swift-stdlib
```

### Additional Resources

```dockerfile
# Copy configuration files
COPY --from=build /build/config.yml ./config.yml

# Copy additional assets
COPY --from=build /build/assets ./assets
```

## Troubleshooting Build Issues

### Common Build Failures

**Swift compilation errors**:
- Check Swift version compatibility
- Verify Package.swift dependencies
- Ensure all required system packages installed

**Missing dependencies**:
```bash
# Debug in build container
container run -it --rm swift:6.2 bash
# Manually run build steps to identify issues
```

**Layer caching issues**:
```bash
# Force rebuild without cache
container build --no-cache -t swift-vapor-server .
```

### Performance Issues

**Slow builds**:
- Use build cache mounts: `--mount=type=cache,target=/build/.build`
- Optimize layer ordering
- Use multi-stage builds effectively

**Large image size**:
- Minimize installed packages
- Use `.containerignore` to exclude unnecessary files
- Clean up build artifacts

### Runtime Issues

**Health check failures**:
```bash
# Test manually
container exec vapor-server curl http://localhost:8080/health

# Check logs
container logs vapor-server
```

**Port binding issues**:
```bash
# Verify port availability
container run -p 8080:8080 --rm swift-vapor-server
# Check for conflicts
```

## Migration from Dockerfile

### Key Differences

| Aspect | Dockerfile (Docker) | Containerfile (Apple) |
|--------|-------------------|----------------------|
| **Base Images** | `ubuntu:20.04` | `ubuntu:noble` |
| **Networking** | `network_mode: host` | Port mapping (`-p`) |
| **Tailscale** | In container | On host |
| **Build Context** | Docker Compose | Manual commands |

### Conversion Steps

1. **Update base images** to newer Ubuntu versions
2. **Remove Tailscale installation** from container
3. **Change networking** from host mode to port mapping
4. **Update build commands** from `docker` to `container`
5. **Move Tailscale** to macOS host

### Compatibility Notes

- **OCI Standard**: Containerfile follows OCI image spec
- **Docker Compatible**: Can be built with Docker if needed
- **Cross-Platform**: Works on macOS, Linux, and other platforms

## Best Practices

### Build Optimization

1. **Layer Caching**: Order instructions to maximize cache hits
2. **Multi-Stage**: Separate build and runtime environments
3. **Minimal Base**: Use smallest possible runtime image
4. **Dependency Management**: Cache dependency resolution

### Security

1. **Non-root User**: Run as unprivileged user
2. **Minimal Packages**: Install only required runtime dependencies
3. **Static Linking**: Reduce dynamic library dependencies
4. **Regular Updates**: Keep base images updated

### Performance

1. **Static Compilation**: Faster startup, smaller memory usage
2. **Optimized Allocators**: Use jemalloc for better memory performance
3. **Health Checks**: Monitor container health
4. **Resource Limits**: Set appropriate CPU/memory limits

### Maintainability

1. **Clear Structure**: Separate concerns across build stages
2. **Documentation**: Comment complex build steps
3. **Version Pinning**: Pin base image versions
4. **Testing**: Validate builds across platforms