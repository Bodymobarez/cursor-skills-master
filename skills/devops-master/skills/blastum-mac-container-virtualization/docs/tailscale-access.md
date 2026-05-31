# Tailscale Network Access Methods

## Overview

Methods for accessing containers running on Apple's container tool through Tailscale networks, including hostname resolution, IP access, and security considerations.

## Access Patterns

### Hostname Access (MagicDNS)

**Automatic hostname resolution:**
```bash
# Access via MagicDNS hostname
curl http://swift-vapor-server:8080/health

# Works from any Tailscale-connected device
# No IP management required
# Automatic DNS updates
```

**Requirements:**
- MagicDNS enabled in Tailscale admin console
- Device approved and connected to tailnet
- Container port exposed via `container run -p`

### Direct IP Access

**Using Tailscale IPs:**
```bash
# Find container host IP
tailscale ip -4

# Access via IP
curl http://100.x.x.x:8080/health

# IPv6 support
tailscale ip -6
curl http://[fd7a:115c:a1e0::1]:8080/health
```

**When to use:**
- MagicDNS not available
- Static IP requirements
- Firewall rule configuration

### Local Access

**Direct localhost access:**
```bash
# When container runs locally
curl http://localhost:8080/health

# Port forwarding through macOS
# No Tailscale required
# Development and testing
```

## Configuration

### Port Mapping

**Expose container ports:**
```bash
# Single port
container run -d -p 8080:8080 swift-vapor-server

# Multiple ports
container run -d \
  -p 8080:8080 \
  -p 8443:443 \
  swift-vapor-server

# Different host port
container run -d -p 9000:8080 swift-vapor-server
```

### Hostname Configuration

**Set custom Tailscale hostname:**
```bash
# Via Tailscale CLI
tailscale up --hostname my-custom-server

# Check current hostname
tailscale status | grep -E "Tailscale IP|Hostname"
```

## Security Considerations

### Network Isolation

**Tailscale ACLs control access:**
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:developers"],
      "dst": ["swift-vapor-server:8080"]
    }
  ]
}
```

### Device Approval

**Require admin approval:**
- New devices appear in admin console
- Manual approval prevents unauthorized access
- Audit trail of device connections

### Access Logging

**Monitor access patterns:**
```bash
# Check active connections
tailscale status

# View device list
tailscale status --json | jq .Peer

# Monitor network traffic
tailscale ping swift-vapor-server
```

## Troubleshooting Access

### DNS Resolution Issues

**MagicDNS not working:**
```bash
# Test DNS resolution
nslookup swift-vapor-server

# Check MagicDNS settings
tailscale status | grep -i dns

# Restart DNS
sudo killall -HUP mDNSResponder
```

### Connection Refused

**Container not accessible:**
```bash
# Check container status
container list

# Verify port mapping
container port swift-vapor-server

# Test local connectivity
container exec swift-vapor-server curl http://localhost:8080/health
```

### Firewall Blocking

**macOS firewall issues:**
```bash
# Check firewall status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Temporarily disable for testing
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
```

## Advanced Access Patterns

### Load Balancing

**Multiple container instances:**
```bash
# Run multiple instances
container run -d -p 8081:8080 --name app-1 swift-vapor-server
container run -d -p 8082:8080 --name app-2 swift-vapor-server

# Load balancer configuration
# Access via shared hostname
```

### Service Discovery

**Automatic service registration:**
```bash
# Services auto-register with Tailscale
# Access via hostname
# No manual IP management
```

### VPN-like Access

**Full network access:**
```bash
# Exit node configuration
tailscale up --advertise-exit-node

# Route all traffic through macOS host
# Access internal networks through Tailscale
```

## Best Practices

### Development Access

1. **Use descriptive hostnames** for easy identification
2. **Enable MagicDNS** for seamless access
3. **Test locally first** before remote access
4. **Document access patterns** for team members

### Production Access

1. **Implement ACLs** for access control
2. **Use HTTPS** for web applications
3. **Monitor access logs** for security
4. **Plan for high availability** with multiple instances

### Security Guidelines

1. **Regular key rotation** for auth keys
2. **Device approval workflow** for new devices
3. **Network segmentation** with ACLs
4. **Audit access patterns** regularly

## Related Topics

- Tailscale Fundamentals - Core Tailscale concepts
- Auth Key Configuration - Authentication setup
- Security Best Practices - Advanced security
- Troubleshooting Guide - Access issue resolution