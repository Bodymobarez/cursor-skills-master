# Common Commands

Essential commands for managing Raspberry Pi via SSH.

## System Information

```bash
# OS and kernel version
uname -a
lsb_release -a

# CPU info
lscpu

# Memory usage
free -h
vmstat 1  # Real-time memory stats

# Disk usage
df -h
du -sh /var/log  # Check log size

# Uptime and load
uptime
```

## Process Management

```bash
# List processes
ps aux
top
htop  # Install: sudo apt install htop

# Kill process
kill <PID>
kill -9 <PID>  # Force kill

# Services
sudo systemctl status ssh
sudo systemctl restart ssh
sudo systemctl enable ssh
```

## File Operations

```bash
# Archive and compress
tar -czf archive.tar.gz directory/
tar -xzf archive.tar.gz

# Find large files
find / -type f -size +100M -exec ls -lh {} \;

# Check disk usage by directory
du -h --max-depth=1 /
```

## Network Configuration

```bash
# Network interfaces
ip addr show
ifconfig

# Routing table
ip route
route -n

# DNS resolution
nslookup google.com
dig google.com

# Open ports
netstat -tlnp
ss -tlnp
```

## Package Management

```bash
# Update system
sudo apt update
sudo apt upgrade
sudo apt autoremove

# Install software
sudo apt install package_name

# Search packages
apt search package_name

# List installed packages
apt list --installed
```

## Temperature Monitoring

```bash
# CPU temperature
vcgencmd measure_temp
cat /sys/class/thermal/thermal_zone0/temp

# Throttling status
vcgencmd get_throttled
```

## Logs and Debugging

```bash
# System logs
journalctl -u ssh
journalctl --since "1 hour ago"

# SSH logs
grep sshd /var/log/auth.log
tail -f /var/log/syslog

# Check SSH config
sudo nano /etc/ssh/sshd_config
sudo systemctl reload ssh
```

## Power Management

```bash
# Shutdown
sudo shutdown -h now

# Reboot
sudo reboot

# Check power supply
vcgencmd get_throttled
```