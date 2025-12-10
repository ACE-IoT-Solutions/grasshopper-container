# Grasshopper Container

Open-source containerized deployment of [Grasshopper](https://github.com/ACE-IoT-Solutions/grasshopper) - a BACnet network visualization and monitoring tool.

[![Build and Publish](https://github.com/ACE-IoT-Solutions/grasshopper-container/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/ACE-IoT-Solutions/grasshopper-container/actions/workflows/build-and-publish.yml)

## What is Grasshopper?

Grasshopper is an open-source project to help understand, manage, and optimize smart building networks. It provides:

- **Autonomous Network Mapping** - Scans and maps BACnet building automation networks
- **Real-time Change Tracking** - Monitors network changes and new devices
- **Interactive Visualization** - Web-based dashboard for network health visualization

## Quick Start

### Using Pre-built Image (Recommended)

```bash
# Pull the latest image
docker pull ghcr.io/ace-iot-solutions/grasshopper-container:latest

# Run with host networking (recommended for BACnet discovery)
docker run -d \
  --name grasshopper \
  --network=host \
  -e BACNET_ADDRESS=192.168.1.100/24:47808 \
  ghcr.io/ace-iot-solutions/grasshopper-container:latest
```

Access the web UI at http://localhost:5000

### Building Locally

```bash
# Clone this repository
git clone https://github.com/ACE-IoT-Solutions/grasshopper-container.git
cd grasshopper-container

# Clone dependencies
./scripts/update-deps.sh

# Build the container
docker build -t grasshopper .

# Run
docker run -d --name grasshopper --network=host \
  -e BACNET_ADDRESS=192.168.1.100/24:47808 \
  grasshopper
```

## Networking Modes

BACnet/IP uses UDP broadcasts for device discovery. The networking mode you choose significantly impacts what devices Grasshopper can discover.

### Host Networking (Recommended for Production)

Host networking gives the container direct access to the host's network interfaces, allowing proper BACnet broadcast discovery.

```bash
docker run -d \
  --name grasshopper \
  --network=host \
  -e BACNET_ADDRESS=192.168.1.100/24:47808 \
  -e WEBAPP_PORT=5000 \
  ghcr.io/ace-iot-solutions/grasshopper-container:latest
```

**Pros:**
- Full BACnet broadcast discovery works
- Can communicate with all devices on the subnet
- Proper integration with BBMDs (BACnet Broadcast Management Devices)

**Cons:**
- Container shares host's network namespace
- Port conflicts possible with host services
- Less isolation

**When to use:** Production deployments where you need to discover all BACnet devices on the network.

### Bridge/NAT Networking (Development/Testing)

Standard Docker networking with port mapping. Limited BACnet functionality but better isolation.

```bash
docker run -d \
  --name grasshopper \
  -p 5000:5000 \
  -p 47808:47808/udp \
  -e BACNET_ADDRESS=0.0.0.0/24:47808 \
  ghcr.io/ace-iot-solutions/grasshopper-container:latest
```

**Pros:**
- Better network isolation
- No port conflicts with host
- Easier to run multiple instances

**Cons:**
- Broadcast discovery limited to container network
- May not discover devices on host network
- BBMD registration may not work correctly

**When to use:** Development, testing, or when connecting to known devices via BBMD/foreign device registration.

### Macvlan Networking (Advanced)

Gives the container its own IP address on the physical network, like a separate machine.

```bash
# Create macvlan network (one-time setup)
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 \
  bacnet-net

# Run with macvlan
docker run -d \
  --name grasshopper \
  --network=bacnet-net \
  --ip=192.168.1.200 \
  -e BACNET_ADDRESS=192.168.1.200/24:47808 \
  ghcr.io/ace-iot-solutions/grasshopper-container:latest
```

**Pros:**
- Container gets its own IP on physical network
- Full BACnet broadcast support
- Good isolation from host

**Cons:**
- More complex setup
- Container cannot communicate with host by default
- Requires promiscuous mode on network interface

**When to use:** When you need full BACnet functionality but want network isolation from the host.

## Environment Variables

### BACnet Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `BACNET_NAME` | `Grasshopper` | BACnet device name |
| `BACNET_INSTANCE` | `708114` | BACnet device instance number |
| `BACNET_ADDRESS` | `0.0.0.0/24:47808` | BACnet address (IP/CIDR:port) |
| `BACNET_NETWORK` | `0` | BACnet network number |
| `BACNET_VENDOR_ID` | `1318` | BACnet vendor identifier |
| `BACNET_FOREIGN` | `null` | Foreign device BBMD address (e.g., `"192.168.1.1"`) |
| `BACNET_TTL` | `30` | Foreign device registration TTL |
| `BACNET_BBMD` | `null` | BBMD address if acting as BBMD |

### Web Interface

| Variable | Default | Description |
|----------|---------|-------------|
| `WEBAPP_ENABLED` | `true` | Enable web interface |
| `WEBAPP_HOST` | `0.0.0.0` | Web server bind address |
| `WEBAPP_PORT` | `5000` | Web server port |
| `WEBAPP_CERTFILE` | `null` | Path to TLS certificate |
| `WEBAPP_KEYFILE` | `null` | Path to TLS private key |

### Scan Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SCAN_INTERVAL_SECS` | `86400` | Interval between network scans (24h) |
| `LOW_LIMIT` | `0` | Lowest device instance to scan |
| `HIGH_LIMIT` | `4194303` | Highest device instance to scan |
| `DEVICE_BROADCAST_FULL_STEP` | `100` | Step size when devices found |
| `DEVICE_BROADCAST_EMPTY_STEP` | `1000` | Step size when no devices |

### VOLTTRON Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `VOLTTRON_VIP_ADDRESS` | `tcp://127.0.0.1:22916` | VOLTTRON VIP address |
| `VOLTTRON_INSTANCE_NAME` | `grasshopper` | VOLTTRON instance name |
| `VOLTTRON_MESSAGE_BUS` | `zmq` | Message bus type |

## Docker Compose Example

```yaml
version: '3.8'

services:
  grasshopper:
    image: ghcr.io/ace-iot-solutions/grasshopper-container:latest
    container_name: grasshopper
    network_mode: host
    environment:
      # BACnet configuration - adjust to your network
      - BACNET_ADDRESS=192.168.1.100/24:47808
      - BACNET_NAME=MyGrasshopper
      - BACNET_INSTANCE=708114

      # Web interface
      - WEBAPP_PORT=5000

      # Scan settings
      - SCAN_INTERVAL_SECS=3600  # Scan every hour
    restart: unless-stopped
    volumes:
      # Persist VOLTTRON data
      - grasshopper-data:/home/volttron/.grasshopper-volttron

volumes:
  grasshopper-data:
```

## Foreign Device Registration

If your network uses BBMDs to manage BACnet broadcasts across subnets, you can register Grasshopper as a foreign device:

```bash
docker run -d \
  --name grasshopper \
  -p 5000:5000 \
  -p 47808:47808/udp \
  -e BACNET_ADDRESS=0.0.0.0/24:47808 \
  -e BACNET_FOREIGN='"192.168.1.1"' \
  -e BACNET_TTL=60 \
  ghcr.io/ace-iot-solutions/grasshopper-container:latest
```

This allows Grasshopper to receive BACnet broadcasts from devices on other subnets through the BBMD.

## Troubleshooting

### Container starts but no devices discovered

1. **Check networking mode**: Use `--network=host` for production
2. **Verify BACNET_ADDRESS**: Must match your network interface IP and subnet
3. **Check firewall**: UDP port 47808 must be open
4. **Verify BACnet devices exist**: Use a known BACnet tool to verify devices are present

### Web UI not accessible

1. **Check WEBAPP_PORT**: Verify port mapping/host port is correct
2. **Check container logs**: `docker logs grasshopper`
3. **Verify container is running**: `docker ps`

### View logs

```bash
# View all logs
docker logs grasshopper

# Follow logs in real-time
docker logs -f grasshopper

# View VOLTTRON logs inside container
docker exec grasshopper cat /tmp/volttron.log
```

## Development

### Building from Source

```bash
# Clone repository
git clone https://github.com/ACE-IoT-Solutions/grasshopper-container.git
cd grasshopper-container

# Fetch dependencies
./scripts/update-deps.sh

# Build image
docker build -t grasshopper:dev .

# Run tests
docker run --rm grasshopper:dev python -c "import grasshopper; print('OK')"
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

- [Grasshopper](https://github.com/ACE-IoT-Solutions/grasshopper) - BACnet network visualization agent
- [VOLTTRON](https://github.com/VOLTTRON/volttron) - Distributed agent platform
- [ACE IoT Solutions](https://aceiotsolutions.com) - Project maintainer

## Related Projects

- [ACE Sentinel](https://aceiotsolutions.com/aerodrome/sentinel/) - Enterprise BACnet network diagnostics
- [BACpypes3](https://github.com/JoelBender/BACpypes3) - BACnet Python library
