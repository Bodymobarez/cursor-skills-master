# Swift Vapor Multi-Platform Support

## Overview

Building Swift Vapor applications that work across different platforms using Apple's container tool, including macOS development and Linux deployment.

## Cross-Platform Containerfile

### Universal Build Pattern

**Platform-agnostic Containerfile:**
```dockerfile
# Multi-platform base image
FROM --platform=$BUILDPLATFORM swift:6.2 AS build

# Cross-platform dependencies
RUN apt-get update && apt-get install -y \
    libjemalloc-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Swift compilation (works on all platforms)
WORKDIR /build
COPY Package.* ./
RUN swift package resolve

COPY . .
RUN swift build -c release \
    --static-swift-stdlib \
    -Xlinker -ljemalloc

# Universal runtime
FROM --platform=$TARGETPLATFORM ubuntu:noble

RUN apt-get update && apt-get install -y \
    libjemalloc2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Runtime setup (platform-independent)
RUN useradd --user-group --create-home vapor
WORKDIR /app
COPY --from=build /build/.build/release/SwiftVaporServer .
USER vapor

EXPOSE 8080
HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1
CMD ["./SwiftVaporServer"]
```

## Platform-Specific Builds

### Apple Silicon (ARM64)

**Native ARM64 build:**
```bash
# Build for Apple Silicon
container build \
  --platform linux/arm64 \
  -t vapor-arm64 \
  .
```

**Performance benefits:**
- Native instruction set
- Optimized for M1/M2/M3
- Better battery life

### Intel/AMD (x86_64)

**x86_64 compatibility:**
```bash
# Build for Intel Macs/Linux
container build \
  --platform linux/amd64 \
  -t vapor-amd64 \
  .
```

**Compatibility requirements:**
- Rosetta 2 on Apple Silicon
- Standard x86_64 Linux

## Development vs Production

### Development Environment

**Local development:**
```bash
# macOS native development
swift run

# Container development
container run -d \
  -p 8080:8080 \
  -v $(pwd):/app \
  --name dev \
  vapor-dev
```

### Production Deployment

**Cross-platform deployment:**
```bash
# Deploy to Linux server
docker run -d \
  --platform linux/amd64 \
  -p 8080:8080 \
  vapor-prod

# Deploy to ARM64 server
docker run -d \
  --platform linux/arm64 \
  -p 8080:8080 \
  vapor-prod
```

## Platform Detection

### Runtime Platform Detection

**Swift platform detection:**
```swift
import Foundation

let platform = ProcessInfo.processInfo.environment["SWIFT_PLATFORM"] ?? "unknown"
print("Running on platform: \(platform)")

// Architecture detection
#if arch(arm64)
    print("ARM64 architecture")
#elseif arch(x86_64)
    print("x86_64 architecture")
#endif
```

### Container Platform Info

**Runtime platform checking:**
```bash
# Check container platform
container inspect vapor-app | jq .Config.Platform

# Runtime architecture
container exec vapor-app uname -m

# Swift version info
container exec vapor-app swift --version
```

## Performance Considerations

### Architecture-Specific Optimization

**ARM64 optimizations:**
```swift
// ARM64-specific code paths
#if arch(arm64)
    // Use NEON instructions
    // Optimize for Apple Silicon
#endif
```

**Memory alignment:**
```swift
// Architecture-aware memory operations
let alignment = MemoryLayout<SomeType>.alignment
// ARM64 prefers 16-byte alignment
```

### Platform-Specific Libraries

**Conditional dependencies:**
```swift
// Platform-specific imports
#if os(Linux)
    import Glibc
#elseif os(macOS)
    import Darwin
#endif
```

## Deployment Strategies

### Multi-Architecture Images

**Build multi-arch images:**
```bash
# Build for multiple platforms
container build \
  --platform linux/arm64,linux/amd64 \
  -t vapor-multiarch \
  .
```

### Platform Selection

**Runtime platform selection:**
```bash
# Automatic platform detection
container run -d \
  --platform linux/$(uname -m) \
  vapor-app
```

## Compatibility Testing

### Platform Testing

**Test on different platforms:**
```bash
# Test ARM64
container run --rm --platform linux/arm64 vapor-app swift --version

# Test x86_64
container run --rm --platform linux/amd64 vapor-app swift --version
```

### Cross-Platform Validation

**Compatibility checks:**
```swift
// Test platform-specific features
func testPlatformCompatibility() {
    #if os(Linux)
        // Linux-specific tests
        assert(access("/proc/version", F_OK) == 0)
    #elseif os(macOS)
        // macOS-specific tests
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sw_vers")
    #endif
}
```

## Migration Between Platforms

### macOS Development to Linux Production

**Development on macOS:**
```bash
# Local development
swift run

# Container development
container build -t vapor-dev .
container run -d -p 8080:8080 vapor-dev
```

**Production on Linux:**
```bash
# Build for Linux
container build \
  --platform linux/x86_64 \
  -t vapor-prod \
  .

# Deploy to Linux server
scp vapor-prod.tar linux-server:
ssh linux-server docker load < vapor-prod.tar
ssh linux-server docker run -d -p 8080:8080 vapor-prod
```

## Best Practices

### Platform Agnostic Development
1. Use cross-platform Swift APIs
2. Avoid platform-specific dependencies when possible
3. Test on multiple architectures
4. Use conditional compilation wisely

### Container Compatibility
1. Use multi-stage builds
2. Minimize platform-specific code
3. Test container behavior across platforms
4. Document platform requirements

### Performance Optimization
1. Optimize for target architecture
2. Use platform-specific libraries when beneficial
3. Profile performance on each platform
4. Balance compatibility with performance

## Troubleshooting

### Architecture Mismatches

**Platform mismatch errors:**
```bash
# Check platform
container inspect app | jq .Config.Platform

# Rebuild for correct platform
container build --platform linux/$(uname -m) -t app .
```

### Library Compatibility

**Missing platform libraries:**
```dockerfile
# Add platform-specific packages
RUN apt-get install -y \
    libssl-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
```

### Performance Issues

**Architecture-specific tuning:**
```swift
// ARM64 memory alignment
let alignedBuffer = UnsafeMutableRawBufferPointer.allocate(
    byteCount: size,
    alignment: 16  // ARM64 preference
)
```

## Related Topics

- Swift Vapor Build Optimization - Build optimization
- Deployment Strategies - Runtime deployment
- Containerfile Structure - Build configuration