# Network Troubleshooting

Find and connect to Raspberry Pi on the network.

## Find Pi IP Address

### Method 1: Network scan (Linux/Mac)
```bash
# Install nmap if needed
# brew install nmap  # macOS
# sudo apt install nmap  # Ubuntu/Debian

nmap -sn 192.168.1.0/24 | grep raspberrypi
```

### Method 2: Avahi/Bonjour (macOS/Linux)
```bash
ping raspberrypi.local
```

### Method 3: Router admin panel
- Log into your router
- Look for devices named "raspberrypi"

### Method 4: From Pi (if you have console access)
```bash
hostname -I  # Shows IP addresses
ip route get 8.8.8.8 | awk '{print $7}'  # Shows default interface IP
```

## Test Connectivity

```bash
# Ping test
ping raspberrypi.local

# SSH test (should see SSH banner)
nc -zv raspberrypi.local 22
```

## Static IP Configuration

### On Pi (via SSH or console)
```bash
# Edit dhcpcd.conf
sudo nano /etc/dhcpcd.conf

# Add at end:
interface wlan0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=8.8.8.8 8.8.4.4

# Restart networking
sudo systemctl restart dhcpcd
```

## Firewall Issues

### Check Pi firewall
```bash
sudo ufw status
sudo ufw allow ssh  # If ufw is active
```

### Check local firewall
```bash
# macOS
sudo pfctl -s info

# Linux
sudo ufw status
sudo iptables -L
```

## Common Issues

- **Connection refused**: SSH service not running, wrong port, firewall
- **Connection timed out**: Wrong IP, network issues, Pi not powered on
- **Permission denied**: Wrong credentials, key not installed
- **Host key verification failed**: SSH key changed, clear known_hosts