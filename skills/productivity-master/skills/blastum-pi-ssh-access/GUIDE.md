---
name: blastum-pi-ssh-access
description: SSH access and management for Raspberry Pi devices. Use when connecting to, managing, or troubleshooting Raspberry Pi systems via SSH.
---

# Pi SSH Access

Manage SSH connections to Raspberry Pi devices.

## Quick Commands

### Connect
```bash
ssh pi@raspberrypi.local
ssh pi@<IP_ADDRESS>
```

### Copy files
```bash
scp file.txt pi@raspberrypi.local:~/
scp pi@raspberrypi.local:~/remote.txt .
```

### Port forwarding
```bash
ssh -L 8080:localhost:80 pi@raspberrypi.local
```

## Resources

- [SSH key setup](docs/keys.md)
- [Network troubleshooting](docs/network.md)
- [Common commands](docs/commands.md)
- [Tailscale HTTPS — Serve, paths, multiple backends](docs/tailscale-https.md)