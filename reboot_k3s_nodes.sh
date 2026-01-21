#!/bin/bash

# Configuration
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CSV_FILE="${SCRIPT_DIR}/node-bmc-ips.csv"
IPMI_USER="root"
IPMI_PASS="root"

if [ ! -f "$CSV_FILE" ]; then
    echo "Error: ${CSV_FILE} not found."
    exit 1
fi

# Load nodes into array
declare -A NODES
HOSTNAMES=()
while IFS=, read -r hostname ip; do
    if [[ "$hostname" != "hostname" ]]; then
        NODES["$hostname"]="$ip"
        HOSTNAMES+=("$hostname")
    fi
done < "$CSV_FILE"

echo "--------------------------------------------------------"
echo "WARNING: YOU ARE ABOUT TO HARD REBOOT THE K3S CLUSTER"
echo "--------------------------------------------------------"
echo "Target Nodes:"
for h in "${HOSTNAMES[@]}"; do
    echo " - $h (${NODES[$h]})"
done
echo "--------------------------------------------------------"

# 1. Verification
echo "To proceed, please type the hostname of the first node ('${HOSTNAMES[0]}'):"
read -r confirmation

if [[ "$confirmation" != "${HOSTNAMES[0]}" ]]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo "Confirmation accepted. Initiating reboot sequence..."

# 2. Execute IPMI Reset
for h in "${HOSTNAMES[@]}"; do
    ip="${NODES[$h]}"
    echo "Rebooting $h ($ip)..."
    if sudo ipmitool -U "$IPMI_USER" -P "$IPMI_PASS" -I lanplus -H "$ip" chassis power reset; then
        echo "  -> Command sent."
    else
        echo "  -> FAILED to send command."
    fi
    # Small gentle delay between blasts
    sleep 1
done

echo "All reboot commands sent."
echo "Waiting for nodes to come back online (SSH check)..."

# 3. Watch for SSH
# We will loop until all nodes are responsive on port 22
START_TIME=$(date +%s)
while true; do
    all_alive=true
    
    # clear screen for dashboard effect (optional, maybe just scroll)
    # echo -e "\033[2J\033[H"
    echo "--- Status Check ($(date +%H:%M:%S)) ---"
    
    for h in "${HOSTNAMES[@]}"; do
        # Using ansible inventory IP would be better, but assuming hostname resolves
        # or we could parse inventory again. For now, try hostname.
        # Check port 22 with timeout
        if nc -z -w 2 "$h" 22 &>/dev/null; then
             echo " [UP]   $h"
        else
             echo " [DOWN] $h"
             all_alive=false
        fi
    done
    
    if $all_alive; then
        echo "--------------------------------------------------------"
        echo "SUCCESS: All nodes are reachable via SSH."
        echo "--------------------------------------------------------"
        break
    fi
    
    ELAPSED=$(($(date +%s) - START_TIME))
    if [ $ELAPSED -gt 600 ]; then
        echo "Timeout waiting for nodes (10 minutes)."
        exit 1
    fi
    
    sleep 5
done
