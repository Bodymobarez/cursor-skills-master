# Container Virtualization Troubleshooting Guide

## Overview

This guide covers common issues and solutions for container virtualization on macOS, focusing on Apple's container tool, Tailscale networking, and Swift Vapor deployments.

## Quick Diagnosis

### System Health Check

```bash
# Check all components at once
echo "=== Container System ==="
container system status

echo "=== Tailscale Status ==="
tailscale status

echo "=== Running Containers ==="
container list

echo "=== Network Connectivity ==="
ping -c 3 swift-vapor-server || echo "Tailscale DNS failed"
curl -f http://localhost:8080/health || echo "Local access failed"
```

## Container System Issues

### "apiserver is not running"

**Symptoms:**
```
Error: apiserver is not running
container system status shows "stopped"
```

**Solutions:**

1. **Start the system:**
   ```bash
   container system start
   ```

2. **Check startup logs:**
   ```bash
   container system logs | tail -20
   ```

3. **Restart system:**
   ```bash
   container system restart
   ```

4. **Check kernel configuration:**
   ```bash
   container system kernel current
   container system kernel set --recommended
   ```

### "kernel not configured"

**Symptoms:**
```
Error: kernel not configured
Build or run commands fail
```

**Solutions:**

1. **Set recommended kernel:**
   ```bash
   container system kernel set --recommended
   ```

2. **List available kernels:**
   ```bash
   container system kernel list
   ```

3. **Set specific kernel:**
   ```bash
   container system kernel set kata
   ```

4. **Check kernel logs:**
   ```bash
   container system logs | grep kernel
   ```

### High Resource Usage

**Symptoms:**
- Slow performance
- High CPU/memory usage
- System becomes unresponsive

**Diagnosis:**
```bash
# Check system resources
container stats

# Check container memory usage
container exec vapor-server ps aux --sort=-%mem | head -10

# Monitor system resources
top -l 1 | head -20
```

**Solutions:**

1. **Restart container system:**
   ```bash
   container system restart
   ```

2. **Check for memory leaks in app:**
   ```bash
   container logs vapor-server | grep -i "memory\|leak\|gc"
   ```

3. **Limit container resources:**
   ```bash
   container run -d \
     --memory 512m \
     --cpus 1.0 \
     -p 8080:8080 \
     swift-vapor-server
   ```

## Build Issues

### Build Failures

**Symptoms:**
```
Error: build failed
Swift compilation errors
```

**Debug Steps:**

1. **Build with verbose output:**
   ```bash
   container build --progress=plain -t debug-build .
   ```

2. **Test in interactive container:**
   ```bash
   container run -it --rm swift:6.2 bash
   # Manually run build steps
   ```

3. **Check Swift version compatibility:**
   ```bash
   swift --version
   cat Package.swift | grep swift-tools-version
   ```

4. **Verify dependencies:**
   ```bash
   container run -it --rm swift:6.2 bash -c "
     git clone <repo> /tmp/test
     cd /tmp/test
     swift package resolve
   "
   ```

### Image Size Issues

**Symptoms:**
- Large image sizes
- Slow downloads/uploads
- Storage space issues

**Solutions:**

1. **Use multi-stage builds:**
   ```dockerfile
   FROM swift:6.2 AS build
   # Build stage

   FROM ubuntu:noble
   # Runtime stage (smaller)
   ```

2. **Clean up build artifacts:**
   ```dockerfile
   RUN apt-get clean && rm -rf /var/lib/apt/lists/*
   ```

3. **Use .containerignore:**
   ```
   .git
   *.md
   tests/
   ```

## Runtime Issues

### Container Won't Start

**Symptoms:**
```
Container exits immediately
Health check fails
```

**Debug Steps:**

1. **Check container logs:**
   ```bash
   container logs vapor-server
   ```

2. **Run in foreground:**
   ```bash
   container run -it --rm -p 8080:8080 swift-vapor-server
   ```

3. **Check health endpoint manually:**
   ```bash
   container exec vapor-server curl http://localhost:8080/health
   ```

4. **Verify startup script:**
   ```bash
   container exec vapor-server cat /app/start.sh
   container exec vapor-server ls -la /app/
   ```

### Port Binding Issues

**Symptoms:**
```
Port already in use
Connection refused
```

**Diagnosis:**
```bash
# Find process using port
lsof -i :8080

# Check container port mapping
container port vapor-server

# Test local connectivity
curl http://localhost:8080/health
```

**Solutions:**

1. **Use different port:**
   ```bash
   container run -d -p 8081:8080 --name vapor-server swift-vapor-server
   ```

2. **Kill conflicting process:**
   ```bash
   kill -9 $(lsof -ti :8080)
   ```

3. **Check firewall settings:**
   ```bash
   sudo pfctl -s rules | grep 8080
   ```

## Networking Issues

### Tailscale Connection Problems

**Symptoms:**
- Can't access via Tailscale hostname
- DNS resolution fails
- Connection timeouts

**Diagnosis:**
```bash
# Check Tailscale status
tailscale status

# Test DNS resolution
nslookup swift-vapor-server

# Test connectivity
tailscale ping swift-vapor-server

# Check ACL rules
# Visit: https://login.tailscale.com/admin/acls
```

**Solutions:**

1. **Restart Tailscale:**
   ```bash
   sudo brew services restart tailscale
   ```

2. **Re-authenticate:**
   ```bash
   tailscale up --reset
   tailscale up
   ```

3. **Check device approval:**
   - Visit admin console
   - Approve pending devices

4. **Verify ACL permissions:**
   ```json
   {
     "acls": [
       {"action": "accept", "src": ["*"], "dst": ["swift-vapor-server:*"]}
     ]
   }
   ```

### Local Access Issues

**Symptoms:**
- `localhost:8080` doesn't work
- Container is running but inaccessible

**Diagnosis:**
```bash
# Check container status
container list

# Verify port mapping
container port vapor-server

# Test from container
container exec vapor-server curl http://localhost:8080/health

# Check host firewall
sudo pfctl -s rules | grep 8080
```

**Solutions:**

1. **Correct port mapping:**
   ```bash
   container run -d -p 8080:8080 --name vapor-server swift-vapor-server
   ```

2. **Check application binding:**
   ```bash
   container exec vapor-server netstat -tlnp | grep 8080
   ```

3. **Verify application logs:**
   ```bash
   container logs vapor-server
   ```

## Swift Application Issues

### Application Crashes

**Symptoms:**
- Container exits with error code
- Swift backtrace in logs
- Memory issues

**Debug Steps:**

1. **Check crash logs:**
   ```bash
   container logs vapor-server
   ```

2. **Enable debug mode:**
   ```bash
   container run -d \
     -e LOG_LEVEL=debug \
     -p 8080:8080 \
     swift-vapor-server
   ```

3. **Test in development mode:**
   ```bash
   swift run  # Local testing
   ```

4. **Check dependencies:**
   ```bash
   container exec vapor-server swift package show-dependencies
   ```

### Performance Issues

**Symptoms:**
- Slow response times
- High CPU usage
- Memory leaks

**Diagnosis:**
```bash
# Monitor application performance
container stats vapor-server

# Check Swift memory usage
container exec vapor-server ps aux | grep SwiftVaporServer

# Profile application
container exec vapor-server swift-backtrace SwiftVaporServer &
```

**Solutions:**

1. **Enable jemalloc:**
   - Already configured in Containerfile
   - Check if it's working: `container exec vapor-server ldd /app/SwiftVaporServer | grep jemalloc`

2. **Optimize Swift build:**
   ```bash
   swift build -c release --static-swift-stdlib -Xlinker -ljemalloc
   ```

3. **Add resource limits:**
   ```bash
   container run -d \
     --memory 1g \
     --cpus 2.0 \
     -p 8080:8080 \
     swift-vapor-server
   ```

## Storage Issues

### Volume Mount Problems

**Symptoms:**
- Files not accessible in container
- Permission denied errors
- Data not persisting

**Diagnosis:**
```bash
# Check volume mounts
container inspect vapor-server | jq .Mounts

# Test file access
container exec vapor-server ls -la /app/data/

# Check host permissions
ls -la /host/path/to/data
```

**Solutions:**

1. **Fix permissions:**
   ```bash
   # On host
   chmod 755 /host/path/to/data

   # Or run container as matching user
   container run -d -u $(id -u):$(id -g) -v /host/path:/container swift-vapor-server
   ```

2. **Use named volumes:**
   ```bash
   container volume create my-data
   container run -d -v my-data:/app/data swift-vapor-server
   ```

### Disk Space Issues

**Symptoms:**
- Build fails with "no space left"
- Container can't write files

**Solutions:**
```bash
# Check disk usage
df -h

# Clean up containers
container rm $(container list -q)

# Clean up images
container image prune -a

# Clean up volumes
container volume prune

# System cleanup
container system prune -a
```

## Platform-Specific Issues

### Apple Silicon Problems

**Symptoms:**
- Rosetta translation warnings
- Performance issues
- Architecture mismatches

**Solutions:**

1. **Use ARM64 native images:**
   ```bash
   container system kernel set --recommended  # ARM64 kernel
   ```

2. **Check architecture:**
   ```bash
   uname -m  # Should show arm64
   container run --rm swift:latest uname -m
   ```

3. **Use correct base images:**
   ```dockerfile
   FROM --platform=linux/arm64 swift:6.2
   FROM --platform=linux/arm64 ubuntu:noble
   ```

### Intel Mac Issues

**Symptoms:**
- x86_64 emulation overhead
- Compatibility issues

**Solutions:**

1. **Use x86_64 kernel:**
   ```bash
   container system kernel set --arch x86_64
   ```

2. **Check Rosetta:**
   ```bash
   # Rosetta should be installed automatically
   pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto
   ```

## Advanced Debugging

### System Logs

```bash
# Container system logs
container system logs

# Tailscale logs
log show --predicate 'subsystem == "tailscale"' --last 1h

# System performance logs
log show --predicate 'subsystem == "com.apple.Virtualization"' --last 1h
```

### Network Debugging

```bash
# Packet capture (requires sudo)
sudo tcpdump -i lo0 port 8080

# Network statistics
netstat -an | grep 8080

# Route table
netstat -r

# DNS resolution
dig swift-vapor-server
```

### Application Profiling

```bash
# CPU profiling
container exec vapor-server perf record -F 99 -p $(pidof SwiftVaporServer)

# Memory profiling
container exec vapor-server valgrind --tool=massif /app/SwiftVaporServer

# Swift backtrace
container exec vapor-server swift-backtrace $(pidof SwiftVaporServer)
```

## Prevention & Monitoring

### Health Checks

**Configure proper health checks:**
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
```

**Monitor health:**
```bash
# Check health status
container inspect vapor-server | jq .State.Health

# View health logs
container logs vapor-server | grep -A5 -B5 health
```

### Logging & Monitoring

**Enable comprehensive logging:**
```bash
# Application logs
container logs -f vapor-server

# System monitoring
container stats vapor-server

# Resource monitoring
docker stats  # If using Docker for monitoring
```

**Log aggregation:**
```bash
# Export logs for analysis
container logs vapor-server > app.log 2>&1

# Monitor log patterns
container logs vapor-server | grep -i "error\|warn\|crash"
```

## Emergency Recovery

### Complete Reset

**When everything fails:**

1. **Stop all containers:**
   ```bash
   container stop $(container list -q)
   ```

2. **Reset container system:**
   ```bash
   container system stop
   container system start
   container system kernel set --recommended
   ```

3. **Reset Tailscale:**
   ```bash
   sudo brew services stop tailscale
   tailscale down
   sudo brew services start tailscale
   tailscale up
   ```

4. **Clean rebuild:**
   ```bash
   container image rm swift-vapor-server
   container build -t swift-vapor-server .
   container run -d -p 8080:8080 --name vapor-server swift-vapor-server
   ```

### Backup & Recovery

**Backup important data:**
```bash
# Export volumes
container run --rm -v my-volume:/data -v $(pwd):/backup alpine tar czf /backup/volume.tar.gz -C /data .

# Backup images
container image save swift-vapor-server > image.tar
```

**Recovery commands:**
```bash
# Restore volume
container run --rm -v my-volume:/data -v $(pwd):/backup alpine tar xzf /backup/volume.tar.gz -C /data

# Restore image
container image load < image.tar
```

## Support Resources

### Documentation
- [Apple Container Tool](https://developer.apple.com/documentation/virtualization)
- [Tailscale Troubleshooting](https://tailscale.com/kb/1007/troubleshooting)
- [Swift Vapor Docs](https://docs.vapor.codes/)

### Community Support
- [Apple Developer Forums](https://developer.apple.com/forums/)
- [Tailscale Community](https://forum.tailscale.com/)
- [Swift Forums](https://forums.swift.org/)

### Professional Support
- [Apple Enterprise Support](https://developer.apple.com/enterprise/)
- [Tailscale Enterprise](https://tailscale.com/enterprise/)
- [Vapor Commercial Support](https://vapor.codes/commercial-support/)