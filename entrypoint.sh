#!/bin/bash
set -e

# Handle shutdown gracefully
shutdown() {
    echo ""
    echo "Shutting down..."

    # Stop tail process if running
    if [ ! -z "$TAIL_PID" ] && ps -p $TAIL_PID > /dev/null 2>&1; then
        kill $TAIL_PID 2>/dev/null || true
    fi

    # Shutdown VOLTTRON directly (don't use vctl since it may hang)
    if [ ! -z "$VOLTTRON_PID" ] && ps -p $VOLTTRON_PID > /dev/null 2>&1; then
        echo "Sending SIGTERM to VOLTTRON..."
        kill -TERM $VOLTTRON_PID 2>/dev/null || true

        # Wait up to 5 seconds for graceful shutdown
        for i in {1..5}; do
            if ! ps -p $VOLTTRON_PID > /dev/null 2>&1; then
                echo "VOLTTRON shutdown complete"
                break
            fi
            sleep 1
        done

        # Force kill if still running
        if ps -p $VOLTTRON_PID > /dev/null 2>&1; then
            echo "Force killing VOLTTRON..."
            kill -9 $VOLTTRON_PID 2>/dev/null || true
        fi
    fi

    echo "Shutdown complete"
    exit 0
}

trap shutdown SIGTERM SIGINT

# Use non-default VOLTTRON_HOME to avoid conflicts with other VOLTTRON instances
export VOLTTRON_HOME=/home/volttron/.grasshopper-volttron
export PYTHONPATH=/code/volttron:$PYTHONPATH
mkdir -p $VOLTTRON_HOME/run

# Kill any existing VOLTTRON processes (handles abstract namespace socket cleanup)
pkill -9 -f "volttron" 2>/dev/null || true
sleep 1

# Clean up any stale IPC sockets and PIDs from previous runs
rm -f $VOLTTRON_HOME/run/vip.socket
rm -f $VOLTTRON_HOME/run/*.pid
rm -f $VOLTTRON_HOME/run/VOLTTRON_PID

echo "==========================================="
echo "Grasshopper Container - BACnet Network Visualization"
echo "==========================================="

# Create VOLTTRON config (always regenerate to ensure correct settings)
echo "Creating VOLTTRON config..."

# Use TCP VIP address for reliable vctl connectivity
VIP_ADDRESS="${VOLTTRON_VIP_ADDRESS:-tcp://127.0.0.1:22916}"

# Build config (let VOLTTRON use default IPC socket location)
cat > $VOLTTRON_HOME/config << EOF
[volttron]
vip-address = ${VIP_ADDRESS}
instance-name = ${VOLTTRON_INSTANCE_NAME:-grasshopper}
message-bus = ${VOLTTRON_MESSAGE_BUS:-zmq}
EOF

echo "VOLTTRON config created with VIP address: ${VIP_ADDRESS}"

# Add permissive auth entry BEFORE starting VOLTTRON
echo "Configuring authentication..."
cat > $VOLTTRON_HOME/auth.json << EOF
{
  "allow": [{"domain": "vip", "address": "/.*/"  , "mechanism": "CURVE", "credentials": "/.*/"  , "user_id": "/.*/"  , "capabilities": {"edit_config_store": null}, "comments": "Allow all CURVE authenticated agents", "enabled": true}]
}
EOF

# Start VOLTTRON in background
echo "Starting VOLTTRON platform..."
cd /code/volttron

volttron -vv -l /tmp/volttron.log &
VOLTTRON_PID=$!

# Wait for VOLTTRON to be ready
echo "Waiting for VOLTTRON to start..."
sleep 5

# Check if VOLTTRON is running
if ! ps -p $VOLTTRON_PID > /dev/null; then
    echo "ERROR: VOLTTRON failed to start"
    cat /tmp/volttron.log
    exit 1
fi

echo "VOLTTRON started successfully (PID: $VOLTTRON_PID)"

# Wait for VOLTTRON to be fully ready by checking if socket exists
echo "Waiting for VOLTTRON platform to be fully initialized..."
for i in {1..30}; do
    # Check if process is still alive
    if ! ps -p $VOLTTRON_PID > /dev/null; then
        echo "ERROR: VOLTTRON process died during startup"
        cat /tmp/volttron.log
        exit 1
    fi

    # Check if VOLTTRON has bound its VIP socket
    if [ -e "$VOLTTRON_HOME/run/vip.socket" ]; then
        echo "VOLTTRON platform is ready"
        sleep 2  # Give it a bit more time to fully initialize
        break
    fi

    if [ $i -eq 30 ]; then
        echo "WARNING: VOLTTRON socket not detected, but continuing anyway..."
        break
    fi
    sleep 1
done

# Create Grasshopper agent config directory
AGENT_CONFIG_DIR="$VOLTTRON_HOME/grasshopper-config"
mkdir -p "$AGENT_CONFIG_DIR"

# Generate Grasshopper configuration from environment variables
echo "Generating Grasshopper configuration..."

# BACnet settings - IMPORTANT for networking mode selection
# For host networking: Use the actual host IP (e.g., 192.168.1.100/24:47808)
# For bridge/namespace networking: Use container IP or 0.0.0.0/24:47808
BACNET_NAME="${BACNET_NAME:-Grasshopper}"
BACNET_INSTANCE="${BACNET_INSTANCE:-708114}"
BACNET_NETWORK="${BACNET_NETWORK:-0}"
BACNET_ADDRESS="${BACNET_ADDRESS:-0.0.0.0/24:47808}"

# Auto-complete BACNET_ADDRESS if only IP is provided
if [[ ! "$BACNET_ADDRESS" =~ "/" ]]; then
    echo "Warning: BACNET_ADDRESS missing CIDR, adding /24"
    BACNET_ADDRESS="${BACNET_ADDRESS}/24"
fi
if [[ ! "$BACNET_ADDRESS" =~ ":" ]]; then
    echo "Warning: BACNET_ADDRESS missing port, adding :47808"
    BACNET_ADDRESS="${BACNET_ADDRESS}:47808"
fi

BACNET_VENDOR_ID="${BACNET_VENDOR_ID:-1318}"
BACNET_FOREIGN="${BACNET_FOREIGN:-null}"
BACNET_TTL="${BACNET_TTL:-30}"
BACNET_BBMD="${BACNET_BBMD:-null}"

# Webapp settings
WEBAPP_ENABLED="${WEBAPP_ENABLED:-true}"
WEBAPP_HOST="${WEBAPP_HOST:-0.0.0.0}"
WEBAPP_PORT="${WEBAPP_PORT:-5000}"
WEBAPP_CERTFILE="${WEBAPP_CERTFILE:-null}"
WEBAPP_KEYFILE="${WEBAPP_KEYFILE:-null}"

# Scan settings
SCAN_INTERVAL_SECS="${SCAN_INTERVAL_SECS:-86400}"
LOW_LIMIT="${LOW_LIMIT:-0}"
HIGH_LIMIT="${HIGH_LIMIT:-4194303}"
DEVICE_BROADCAST_FULL_STEP="${DEVICE_BROADCAST_FULL_STEP:-100}"
DEVICE_BROADCAST_EMPTY_STEP="${DEVICE_BROADCAST_EMPTY_STEP:-1000}"

# Create Grasshopper config.json
cat > "$AGENT_CONFIG_DIR/config" << EOF
{
    "scan_interval_secs": ${SCAN_INTERVAL_SECS},
    "low_limit": ${LOW_LIMIT},
    "high_limit": ${HIGH_LIMIT},
    "device_broadcast_full_step_size": ${DEVICE_BROADCAST_FULL_STEP},
    "device_broadcast_empty_step_size": ${DEVICE_BROADCAST_EMPTY_STEP},
    "bacpypes_settings": {
        "name": "${BACNET_NAME}",
        "instance": ${BACNET_INSTANCE},
        "network": ${BACNET_NETWORK},
        "address": "${BACNET_ADDRESS}",
        "vendoridentifier": ${BACNET_VENDOR_ID},
        "foreign": ${BACNET_FOREIGN},
        "ttl": ${BACNET_TTL},
        "bbmd": ${BACNET_BBMD}
    },
    "webapp_settings": {
        "enabled": ${WEBAPP_ENABLED},
        "host": "${WEBAPP_HOST}",
        "port": ${WEBAPP_PORT},
        "certfile": ${WEBAPP_CERTFILE},
        "keyfile": ${WEBAPP_KEYFILE}
    }
}
EOF

echo "Grasshopper configuration created at: $AGENT_CONFIG_DIR/config"
cat "$AGENT_CONFIG_DIR/config"

# Install Grasshopper agent
cd /code/volttron
echo "Installing Grasshopper agent..."

# Install with --start flag
vctl install /code/grasshopper-repo/Grasshopper \
    --agent-config "$AGENT_CONFIG_DIR/config" \
    --tag grasshopper \
    --vip-identity grasshopper \
    --start 2>&1 | tee /tmp/grasshopper-install.log

if [ $? -eq 0 ]; then
    echo "Grasshopper agent installed successfully"
    INSTALL_SUCCESS=true
else
    echo "WARNING: Failed to install Grasshopper agent"
    cat /tmp/grasshopper-install.log
    INSTALL_SUCCESS=false
fi

echo "========================================="
echo "Container ready!"
echo "VOLTTRON Platform: Running (PID: $VOLTTRON_PID)"

# Check if Grasshopper web UI is actually accessible
echo "Checking Grasshopper web UI..."
WEB_UI_RUNNING=false
for i in {1..10}; do
    if curl -s http://localhost:${WEBAPP_PORT}/ > /dev/null 2>&1; then
        echo "Grasshopper Agent: Running"
        echo "Web UI: http://${WEBAPP_HOST}:${WEBAPP_PORT}"
        WEB_UI_RUNNING=true
        break
    fi
    sleep 2
done

if [ "$WEB_UI_RUNNING" != "true" ]; then
    echo "WARNING: Grasshopper web UI not responding on port ${WEBAPP_PORT}"
    echo "Agent may still be starting up or failed to start"
fi

echo ""
echo "Networking Mode:"
if [ "$BACNET_ADDRESS" = "0.0.0.0/24:47808" ]; then
    echo "  Using default address - for BACnet discovery, use --network=host"
    echo "  Or set BACNET_ADDRESS to your network interface IP"
else
    echo "  BACnet Address: $BACNET_ADDRESS"
fi
echo "========================================="

# Follow VOLTTRON logs in background so trap can execute
tail -f /tmp/volttron.log &
TAIL_PID=$!

# Wait for VOLTTRON process instead of tail
# This allows proper signal handling
wait $VOLTTRON_PID
