# Tailscale Networking Fundamentals

## Overview

Tailscale provides secure, zero-trust networking for containers on macOS. Unlike traditional VPNs, Tailscale uses WireGuard for direct device-to-device connections with automatic key management.

## How Tailscale Works

### Core Concepts

**Tailnet**: Your private network of devices
**Nodes**: Devices connected to your tailnet (servers, laptops, phones)
**Auth Keys**: Credentials for joining devices
**ACLs**: Access control rules between devices
**MagicDNS**: Automatic hostname resolution

### Architecture

```
Your Devices
    ↓ (Tailscale app/daemon)
Tailscale Coordination Server (tailscale.com)
    ↓ (control plane)
WireGuard Tunnels (direct device-to-device)
    ↓
Secure Networking (encrypted, authenticated)
```

### Key Benefits for Containers

- **Zero Configuration**: No port forwarding or firewall rules
- **End-to-End Encryption**: All traffic automatically encrypted
- **NAT Traversal**: Works behind firewalls and NAT
- **Device-Based Access**: Control access per device, not IP ranges
- **MagicDNS**: Access devices by hostname instead of IP

## Installation & Setup

### macOS Host Installation

```bash
# Install Tailscale
brew install tailscale

# Start service
sudo brew services start tailscale

# Initial authentication (opens browser)
tailscale up

# Verify connection
tailscale status
```

### Container Installation (Alternative)

For containers that need Tailscale inside:

```bash
# Dockerfile/Containerfile
FROM ubuntu:22.04

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Run Tailscale
CMD ["tailscaled"] &
    tailscale up --auth-key=$TAILSCALE_AUTH_KEY
```

## Authentication Methods

### Auth Keys (Recommended for Containers)

**Types:**
- **Ephemeral**: Auto-expire, single-use, perfect for containers
- **Reusable**: Long-lived, can be revoked, for persistent services

**Creating Auth Keys:**
1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/authkeys)
2. Click "Generate auth key"
3. Configure:
   - **Type**: Ephemeral (recommended)
   - **Description**: swift-vapor-server
   - **Expiry**: 90 days
   - **Tags**: (leave empty for full access)

### Interactive Authentication (For Development)

```bash
# On device with browser access
tailscale up

# Follow browser authentication flow
# Device appears in admin console for approval
```

## Network Access Patterns

### Local Development Access

```
Browser → localhost:8080 → Container on macOS
```

**When to use:**
- Development and testing
- No remote access needed
- Simple localhost connections

### Tailscale Network Access

```
Browser → swift-vapor-server:8080 → Tailscale → Container on macOS
```

**When to use:**
- Remote access from any device
- Secure access from anywhere
- Team collaboration

### Hybrid Access (Both)

```
Container exposes both:
- localhost:8080 (local development)
- tailscale-ip:8080 (remote access)
- swift-vapor-server:8080 (MagicDNS)
```

## Configuration Options

### Basic Setup

```bash
# Simple auth with key
tailscale up --auth-key=tskey-...

# With custom hostname
tailscale up --auth-key=tskey-... --hostname=my-server

# Accept routes (for subnet access)
tailscale up --auth-key=tskey-... --accept-routes
```

### Advanced Configuration

```bash
# Disable MagicDNS (use IPs only)
tailscale up --auth-key=tskey-... --accept-dns=false

# Custom DNS servers
tailscale up --auth-key=tskey-... --dns=8.8.8.8,1.1.1.1

# Exit node (route all traffic through this device)
tailscale up --auth-key=tskey-... --advertise-exit-node
```

## Security Model

### Zero-Trust Networking

**Traditional VPN:**
```
Internet → VPN Server → Private Network → Your Server
(All traffic goes through VPN server)
```

**Tailscale:**
```
Device A → Direct WireGuard → Device B
(Point-to-point encrypted tunnels)
```

### Access Control

**Default Policy**: All devices in tailnet can reach each other

**Custom ACLs**: Granular control via JSON policy:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["alice@*"],
      "dst": ["server:*"]
    }
  ]
}
```

### Device Approval

- New devices appear in admin console
- Require manual approval for security
- Can auto-approve trusted devices

## Integration with Containers

### Host-Based Tailscale (Recommended)

```bash
# Tailscale runs on macOS host
# Container uses standard networking
# Access via hostname or IP

macOS Host
├── Tailscale Daemon
└── Container (port 8080)
    ↓
Browser → swift-vapor-server:8080
```

**Advantages:**
- Lower container complexity
- Better macOS integration
- Easier debugging
- Works with Apple's container tool

### Container-Based Tailscale

```bash
# Tailscale runs inside container
# Requires host networking or TUN access
# More complex setup

Container
├── App (port 8080)
└── Tailscale Daemon
    ↓
Direct Tailscale networking
```

**When to use:**
- Docker Desktop with host networking
- Need Tailscale features inside container
- Legacy setups

## Monitoring & Troubleshooting

### Status Checking

```bash
# Basic status
tailscale status

# Detailed status
tailscale ping swift-vapor-server

# Network information
tailscale ip -4  # IPv4 address
tailscale ip -6  # IPv6 address

# List all devices
tailscale status --json | jq .Peer
```

### Connection Testing

```bash
# Test connectivity
ping swift-vapor-server

# Test specific port
telnet swift-vapor-server 8080

# Test with curl
curl http://swift-vapor-server:8080/health
```

### Debug Logging

```bash
# Enable debug logging
tailscale debug --enable

# View logs
tailscale debug --logs

# Check system logs
log show --predicate 'subsystem == "tailscale"' --last 1h
```

### Common Issues

**"Tailscale is stopped"**
```bash
sudo brew services restart tailscale
tailscale up
```

**"Device not approved"**
- Check admin console for pending devices
- Approve device or check ACL rules

**DNS resolution fails**
```bash
# Check MagicDNS settings
tailscale status | grep -i dns

# Test resolution
nslookup swift-vapor-server

# Restart DNS
sudo killall -HUP mDNSResponder
```

**Connection timeouts**
```bash
# Check firewall settings
tailscale ping --timeout=10s swift-vapor-server

# Test different ports
tailscale ping --port=8080 swift-vapor-server
```

## Performance Considerations

### Network Latency

- **Direct connections**: ~0.1-1ms latency
- **Via DERP**: 50-200ms (fallback for difficult NAT)
- **Through exit node**: Additional routing latency

### Bandwidth

- **WireGuard efficiency**: Near wire-speed performance
- **Compression**: Automatic for better throughput
- **MTU**: Optimized for various networks

### Resource Usage

- **Memory**: ~10-20MB per device
- **CPU**: Minimal (~0.1% idle, <1% under load)
- **Battery**: Optimized for mobile devices

## Best Practices

### For Development

1. **Use ephemeral keys** for containers
2. **Enable MagicDNS** for easy hostnames
3. **Test locally first** before remote access
4. **Use descriptive hostnames** for device identification

### For Production

1. **Implement ACLs** for access control
2. **Use reusable keys** sparingly, with monitoring
3. **Enable device approval** for new devices
4. **Monitor device status** and key usage
5. **Plan key rotation** strategy

### Security Recommendations

1. **Regular key rotation** (ephemeral keys auto-rotate)
2. **Monitor admin console** for unauthorized devices
3. **Use tags and ACLs** for role-based access
4. **Enable logging** for audit trails
5. **Keep Tailscale updated** for security patches

## Integration Examples

### With Apple's Container Tool

```bash
# Container runs normally
container run -d -p 8080:8080 swift-vapor-server

# Tailscale provides access
# Access via: http://swift-vapor-server:8080
```

### With Docker/Colima

```bash
# Host networking for Tailscale in container
docker run --network host \
  -e TAILSCALE_AUTH_KEY=tskey-... \
  swift-vapor-server
```

### With Docker Compose

```yaml
version: '3.8'
services:
  app:
    image: swift-vapor-server
    network_mode: host
    environment:
      - TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - tailscale-data:/var/lib/tailscale
```

## Migration Strategies

### From Traditional VPN

1. **Install Tailscale** on all devices
2. **Create auth keys** for servers
3. **Update access patterns** (hostnames vs IPs)
4. **Configure ACLs** to match VPN rules
5. **Test connectivity** before removing VPN

### From ngrok/LocalTunnel

1. **Replace tunnel commands** with Tailscale
2. **Update access URLs** in documentation
3. **Configure ACLs** for team access
4. **Add monitoring** for uptime

### From Port Forwarding

1. **Remove port forwarding rules**
2. **Install Tailscale** on server
3. **Use hostnames** for access
4. **Configure firewall** to block direct access

## Resources

- [Tailscale Documentation](https://tailscale.com/kb/)
- [ACL Policy Language](https://tailscale.com/kb/1018/acls)
- [Admin Console](https://login.tailscale.com/admin)
- [Security Best Practices](https://tailscale.com/kb/1007/security-audit)