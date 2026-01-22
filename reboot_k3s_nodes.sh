#!/bin/bash

# Configuration
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
# Primary source: Updated IPMI Discovery
DISCOVERY_FILE="/home/nathan/ipmi/bmc_discovery_20260122.csv"
IPMI_USER="root"
IPMI_PASS="root"

if [ -f "$DISCOVERY_FILE" ]; then
    CSV_FILE="$DISCOVERY_FILE"
    FORMAT="NEW"
elif [ -f "${SCRIPT_DIR}/node-bmc-ips.csv" ]; then
    CSV_FILE="${SCRIPT_DIR}/node-bmc-ips.csv"
    FORMAT="LEGACY"
    echo "Warning: Using legacy inventory file."
else
    echo "Error: No inventory CSV found."
    exit 1
fi

# Load nodes into array
declare -A NODES
HOSTNAMES=()

if [[ "$FORMAT" == "NEW" ]]; then
    # Parse: IP,HOSTNAME,MAC
    while IFS=, read -r ip hostname mac; do
        ip=$(echo "$ip" | tr -d '[:space:]')
        hostname=$(echo "$hostname" | tr -d '[:space:]')
        
        if [[ "$ip" == "IP" ]]; then continue; fi
        if [[ "$hostname" == "UNKNOWN" || -z "$hostname" ]]; then continue; fi
        
        NODES["$hostname"]="$ip"
        HOSTNAMES+=("$hostname")
    done < "$CSV_FILE"
else
    # Parse: hostname,bmc_ip
    while IFS=, read -r hostname ip; do
        if [[ "$hostname" != "hostname" ]]; then
            NODES["$hostname"]="$ip"
            HOSTNAMES+=("$hostname")
        fi
    done < "$CSV_FILE"
fi

# Sort for display
IFS=$'\n' HOSTNAMES=($(sort <<<"${HOSTNAMES[*]}"))
unset IFS

if [[ ${#HOSTNAMES[@]} -eq 0 ]]; then
    echo "Error: No valid hostnames found in $CSV_FILE"
    exit 1
fi

# Handle Arguments
TARGET_ARGS=("$@")

if [[ ${#TARGET_ARGS[@]} -eq 0 ]]; then
    echo "--------------------------------------------------------"
    echo "WARNING: YOU ARE ABOUT TO HARD REBOOT THE ENTIRE CLUSTER"
    echo "--------------------------------------------------------"
    echo "Source: $CSV_FILE"
    echo "Target Nodes:"
    for h in "${HOSTNAMES[@]}"; do
        echo " - $h (${NODES[$h]})"
    done
    echo "--------------------------------------------------------"

    # Verification
    echo "To proceed, please type the hostname of the first node ('${HOSTNAMES[0]}'):"
    read -r confirmation

    if [[ "$confirmation" != "${HOSTNAMES[0]}" ]]; then
        echo "Confirmation failed. Aborting."
        exit 1
    fi

    echo "Confirmation accepted. Initiating reboot sequence..."
    TARGETS=("${HOSTNAMES[@]}")
else
    echo "Targeting specific nodes: ${TARGET_ARGS[*]}"
    TARGETS=()
    for t in "${TARGET_ARGS[@]}"; do
        if [[ -z "${NODES[$t]}" ]]; then
            echo "Error: Node '$t' not found in inventory."
            exit 1
        fi
        TARGETS+=("$t")
    done
fi

# Execute IPMI Reset
for h in "${TARGETS[@]}"; do
    ip="${NODES[$h]}"
    echo "Rebooting $h ($ip)..."
    if sudo ipmitool -U "$IPMI_USER" -P "$IPMI_PASS" -I lanplus -H "$ip" chassis power reset; then
        echo "  -> Command sent."
    else
        echo "  -> FAILED to send command to $h"
    fi
done

echo "Done."
