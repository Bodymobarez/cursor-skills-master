# Node.js TypeScript Containerfile Structure

## Overview

This guide explains the Containerfile used for Node.js TypeScript webapp deployment, optimized for Apple's native container runtime on macOS with Tailscale networking.

## Containerfile Architecture

### Multi-Stage Build Pattern

```
Build Stage (node:20-alpine)
    ↓ Dependencies
    ↓ TypeScript Compilation
    ↓ JavaScript Bundling
    ↓ Runtime Preparation
    ↓
Runtime Stage (node:20-alpine)
    ↓ Minimal Runtime
    ↓ Security Hardening
    ↓ Health Checks
    ↓ Final Image
```

### Key Optimizations

- **TypeScript Compilation**: Separate build stage for compilation
- **Dependency Layering**: Production vs development dependencies
- **Process Manager**: dumb-init for proper signal handling
- **Security**: Non-root user, minimal attack surface
- **Health Checks**: Container monitoring with curl

## Detailed Build Stages

### Stage 1: TypeScript Build Environment

```dockerfile
FROM node:20-alpine AS build

# Install build dependencies
RUN apk add --no-cache \
    curl \
    ca-certificates

# Set working directory
WORKDIR /build
```

**Purpose**: Provides Node.js runtime and build tools
**Size**: ~150MB (includes full Node.js toolchain)
**Key packages**:
- `curl`: For health checks and networking
- `ca-certificates`: SSL certificate validation

### Dependency Management

```dockerfile
# Copy package files for dependency caching
COPY package*.json ./

# Install dependencies (including dev dependencies for build)
RUN npm install
```

**Optimization**: Separate dependency installation from source code
**Benefit**: Faster rebuilds when only source code changes
**Cache Layer**: Docker layer cache preserves node_modules

### TypeScript Compilation

```dockerfile
# Copy source code
COPY . .

# Build TypeScript to JavaScript
RUN npm run build
```

**Process**:
- Copies TypeScript source from `src/`
- Compiles to JavaScript in `dist/`
- Preserves source maps for debugging

### Stage 2: Runtime Environment

```dockerfile
FROM node:20-alpine

# Install minimal runtime dependencies
RUN apk add --no-cache \
    curl \
    ca-certificates \
    dumb-init

# Create app user and group
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001
```

**Base Image**: Alpine Linux with Node.js 20
**Runtime Dependencies**:
- `dumb-init`: Proper process signal handling
- `curl`: Health check command
- `ca-certificates`: SSL certificates for HTTPS

### Security and User Setup

```dockerfile
# Set working directory
WORKDIR /app

# Copy built application from build stage
COPY --from=build --chown=nextjs:nodejs /build/dist ./dist
COPY --from=build --chown=nextjs:nodejs /build/node_modules ./node_modules
COPY --from=build --chown=nextjs:nodejs /build/package*.json ./

# Switch to non-root user
USER nextjs:nodejs
```

**Security Features**:
- Non-root user (`nextjs:nodejs`)
- UID 1001 to avoid conflicts
- Proper file ownership
- Dedicated application directory

### Environment Configuration

```dockerfile
# Environment variables
ENV NODE_ENV=production
ENV PORT=8080
ENV HOSTNAME=0.0.0.0

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Start application
ENTRYPOINT ["dumb-init", "--"]
CMD ["npm", "start"]
```

**Health Check Parameters**:
- `--interval=30s`: Check every 30 seconds
- `--timeout=3s`: Fail if check takes longer than 3 seconds
- `--start-period=5s`: Wait 5 seconds after startup
- `--retries=3`: Allow 3 failures before marking unhealthy

## Build Process Deep Dive

### Layer Optimization

**Build Layer Caching**:
```
Layer 1: Base Node.js image (cached)
Layer 2: System dependencies (cached)
Layer 3: Dependency resolution (cached if package*.json unchanged)
Layer 4: Source code copy (changes often)
Layer 5: TypeScript compilation (changes with source)
Layer 6: Runtime Node.js base (cached)
Layer 7: Runtime dependencies (cached)
Layer 8: User creation (cached)
Layer 9: Binary and resources copy (changes with build)
```

### Build Context

**What gets sent to container**:
```
nodejs-app/
├── Containerfile
├── package.json
├── package-lock.json
├── tsconfig.json
├── src/
│   └── server.ts
└── dist/ (generated)
```

**Optimizations**:
- Use `.containerignore` to exclude unnecessary files
- Keep context small for faster builds
- Include only required source files

### TypeScript Configuration

**Recommended tsconfig.json**:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### Package.json Scripts

```json
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/server.js",
    "dev": "ts-node src/server.ts"
  }
}
```

## Runtime Behavior

### Startup Sequence

1. **Container starts** as `nextjs` user
2. **dumb-init** handles process signals properly
3. **npm start** launches Node.js application
4. **Health check** begins monitoring `/health` endpoint
5. **Application** binds to `0.0.0.0:8080`

### Process Management

**dumb-init Integration**:
- Properly handles SIGTERM/SIGINT signals
- Reaps zombie processes
- Ensures clean shutdown
- Required for Node.js in containers

**NPM Scripts**:
- `npm start` runs production build
- `npm run dev` uses ts-node for development
- Scripts can be customized per application

### Networking

**Container Networking**:
- Binds to all interfaces (`0.0.0.0`)
- Port 8080 exposed for external access
- Works with both localhost and Tailscale access

**Tailscale Integration**:
- No Tailscale daemon in container (host-based)
- Standard port mapping
- Hostname resolution via MagicDNS

## Comparison with Swift Containers

| Aspect | Node.js Container | Swift Container |
|--------|------------------|-----------------|
| **Build Tool** | npm/TypeScript | Swift Package Manager |
| **Compilation** | TypeScript → JavaScript | Swift → Binary |
| **Runtime** | Node.js interpreter | Static binary |
| **Dependencies** | package.json | Package.swift |
| **Process Manager** | dumb-init | Direct binary |
| **Build Stages** | 2 stages | 2 stages |
| **Security** | Non-root user | Non-root user |
| **Health Checks** | curl to /health | curl to /health |

## Customization Examples

### Adding Native Dependencies

```dockerfile
# In build stage
RUN apk add --no-cache \
    python3 \
    make \
    g++

# Install node-gyp dependencies
RUN npm install -g node-gyp
```

### Environment-Specific Builds

```dockerfile
# Development build
RUN npm run build:dev

# Production build (optimized)
RUN npm run build:prod
```

### Additional Resources

```dockerfile
# Copy configuration files
COPY --from=build /build/config.yml ./config.yml

# Copy static assets
COPY --from=build /build/public ./public
```

## Troubleshooting Build Issues

### Common Build Failures

**TypeScript compilation errors**:
- Check TypeScript version compatibility
- Verify tsconfig.json settings
- Ensure all required type definitions installed

**Missing dependencies**:
```bash
# Debug in build container
container run -it --rm node:20-alpine sh
# Manually run build steps to identify issues
```

**Layer caching issues**:
```bash
# Force rebuild without cache
container build --no-cache -t nodejs-app .
```

### Runtime Issues

**Health check failures**:
```bash
# Test manually
container exec nodejs-app curl http://localhost:8080/health

# Check logs
container logs nodejs-app
```

**Permission issues**:
```bash
# Check file ownership
container exec nodejs-app ls -la /app

# Verify user
container exec nodejs-app whoami
```

### Performance Issues

**Slow builds**:
- Use build cache mounts: `--mount=type=cache,target=/root/.npm`
- Optimize layer ordering
- Use multi-stage builds effectively

**Large image size**:
- Minimize installed packages in runtime
- Use `.containerignore` to exclude files
- Clean up build artifacts

## Best Practices

### Build Optimization

1. **Layer Caching**: Order instructions to maximize cache hits
2. **Multi-Stage**: Separate build and runtime environments
3. **Minimal Runtime**: Use smallest possible runtime image
4. **Dependency Management**: Cache node_modules effectively

### Security

1. **Non-root User**: Run as unprivileged user
2. **Minimal Packages**: Install only required runtime dependencies
3. **Regular Updates**: Keep base images updated
4. **Environment Variables**: Don't hardcode secrets

### Performance

1. **TypeScript Compilation**: Compile once, run optimized JS
2. **Process Manager**: Use dumb-init for proper signal handling
3. **Health Checks**: Monitor container health
4. **Resource Limits**: Set appropriate CPU/memory limits

### Maintainability

1. **Clear Structure**: Separate concerns across build stages
2. **Documentation**: Comment complex build steps
3. **Version Pinning**: Pin Node.js and Alpine versions
4. **Testing**: Validate builds across environments