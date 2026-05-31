# Apple's Container Tool Overview

## Architecture Overview

```
macOS Host (Darwin Kernel)
├── Tailscale Daemon (host networking)
├── Apple's Container Tool
│   ├── Kata Containers Micro-VM #1
│   │   └── Ubuntu Container
│   │       └── Swift Vapor App
│   ├── Kata Containers Micro-VM #2
│   │   └── Alpine Container
│   │       └── Node.js TypeScript App
│   └── Additional Micro-VMs...
└── Virtualization.framework
```

**Key Benefits:**
- Micro-VM per container for better isolation
- Support for multiple languages (Swift, Node.js, Python, etc.)
- Tailscale on host for simpler networking
- Native macOS performance optimization
- Apple Silicon hardware acceleration

## Quick Start

For immediate setup:
1. **Install**: `brew install container && container system start`
2. **Setup Tailscale**: `brew install tailscale && tailscale up`
3. **Deploy**: `container build -t app . && container run -d -p 8080:8080 app`

## Quick Reference

### Basic Commands
```bash
# Build and run
container build -t app .
container run -d -p 8080:8080 app

# Monitor and debug
container list
container logs app
container exec -it app bash
```

### Common Patterns
```bash
# Development with source mounting
container run -d -p 8080:8080 -v $(pwd):/app app

# Production with resource limits
container run -d --memory 512m --cpus 1.0 -p 8080:8080 app

# With Tailscale access
tailscale up --auth-key=tskey-...  # On host
container run -d -p 8080:8080 app  # Container
curl http://app-hostname:8080      # Access via Tailscale
```

## Performance Benefits

| Aspect | Apple Container | Docker Desktop |
|--------|----------------|----------------|
| **Memory Usage** | ~230MB per container | 1.5-2GB baseline |
| **Startup Time** | 1-2 seconds | 30-60 seconds |
| **CPU Overhead** | 0.1-0.5% idle | 1-2% idle |
| **Architecture** | Micro-VM isolation | Shared VM |

## Migration Path

**From Docker Desktop:**
1. Replace `docker` commands with `container`
2. Remove `network_mode: host` (use port mapping)
3. Move Tailscale to macOS host
4. Update build contexts and arguments

**From Other Tools:**
- Commands are OCI-compatible
- Networking uses standard patterns
- Build processes remain similar

## Support & Resources

For help with specific issues:
- **Installation Issues**: Check Apple Container Tool setup documentation
- **Networking Problems**: Review Tailscale fundamentals and configuration
- **Build Failures**: Examine Swift Vapor containerfile patterns
- **Runtime Errors**: Use the troubleshooting guide

## Getting Help

1. Check command reference for syntax
2. Review troubleshooting guide for common issues
3. See migration guide for Docker transition
4. Verify performance tuning for optimization