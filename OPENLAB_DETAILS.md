# Openlab @ UT Dallas - K3s Cluster Details

## Overview
These notes document the architecture, configuration, and operational details of the K3s cluster running at **Openlab @ UT Dallas**. This cluster supports the dissertation research involving the **ONE-Engine** (Optical Network Emulation Engine).

## Architecture

### Topology: "Speed Run" Optimized
The cluster uses a dedicated Control Plane architecture designed for stability and resource efficiency. We explicitly separated the control plane from the worker nodes to prevent user workloads (which are memory-intensive) from starving the Kubernetes API server and etcd database.

**Summary:**
- **Total Nodes:** 23 Physical Servers
- **Control Plane:** 3 Dedicated Nodes (High Availability)
- **Workers:** 20 High-Capacity Nodes

### Node Selection Strategy
To optimize resource usage:
1.  **Memory Binning:** We identified nodes with lower RAM (<64GB) and assigned them to the **Control Plane**. Since the Control Plane is CPU-bound but not heavily RAM-bound for our scale, this maximizes the utility of "weaker" hardware.
2.  **Workers:** We reserved the high-RAM nodes (128GB+) strictly for **Worker** roles to support the heavy memory footprint of ONE-Engine simulations.
3.  **Physical Distribution:** To ensure resilience against chassis power/switch failures, the 3 Control Plane nodes are distributed across different physical hardware groups:
    - `marconi3` (Dell DCS8000Z - Chassis 3 "Marconi")
    - `pve-teach-147` (Dell DCS8000Z - Chassis 1 "PVE")
    - `pve-teach-150` (Dell DCS8000Z - Chassis 2 "PVE")

### Detailed Inventory

#### Control Plane (Masters)
These nodes are tainted to prevent standard pods from scheduling on them.
`Taint: CriticalAddonsOnly=true:NoSchedule`

| Hostname | IP Address | Ansible User | Physical Location | Role |
|----------|------------|--------------|-------------------|------|
| `marconi3` | 10.203.248.233 | `openlab` | Chassis 3 | **Leader** (API Endpoint) |
| `pve-teach-147` | 10.203.248.147 | `root` | Chassis 1 | HA Member |
| `pve-teach-150` | 10.203.248.150 | `root` | Chassis 2 | HA Member |

#### Workers (Agents)
These nodes handle all user workloads.

- **Chassis 3 (Marconi):** `marconi1`, `marconi2`, `marconi4` through `marconi8`.
- **Chassis 1:** `pve-teach-140` through `pve-teach-146` (Node `147` serves as Control Plane).
- **Chassis 2:** `pve-teach-133`, `pve-teach-134`, `pve-teach-136` through `pve-teach-139` (Node `150` serves as Control Plane).
  *(Note: `pve-teach-135` in Chassis 2 is reserved as a Jumpbox. Numbering skips significantly between 139 and 150).*

## Configuration & Deployment

### Prerequisites & Access
The lab operates a mixed environment of OS installs:
- **Legacy Nodes (`marconi`):** User `openlab` with sudo capabilities.
- **Newer Nodes (`pve-teach`):** User `root`.

Ansible handles this complexity via `inventory.yml` variables:
```yaml
pve-teach-147:
  ansible_user: root
marconi3:
  # defaults to 'openlab' from group vars
```
**SSH Keys:** Distributed using `distribute_ssh_key.yml` to ensure password-less automation.

### Ansible Playbooks
We use a streamlined set of playbooks to manage the lifecycle:

1.  **`reset.yml`**: The "Nuke" option. Completely uninstalls K3s, removes binaries, and cleans up `/etc/rancher`. Used to pivot from the old "Hyper-Converged" architecture to the new "Dedicated Control Plane" architecture.
2.  **`site.yml`**: The main installer.
    -   **Prereq Phase:** Disables swap, configures sysctl.
    -   **Download:** Fetches K3s binaries to the control node first (airgap style efficiency).
    -   **Server Setup:** Bootstraps the first node (`marconi3`), then joins the other two.
    -   **Agent Setup:** Joins the 20 worker nodes.
3.  **`fix_registry.yml`**: Post-install configuration to inject the private registry mirror settings.

### Private Registry
The cluster is configured to pull images from a local Synology NAS to avoid Docker Hub rate limits and speed up deployments.

- **Address:** `10.203.247.224:5050`
- **Config Loc:** `/etc/rancher/k3s/registries.yaml`

## Operational Notes

### InfiniBand
OpenSM (Subnet Manager) is configured to run on specific nodes to manage the high-speed InfiniBand fabric. While `marconi1` and `marconi2` are now agents, they still act as the primary locations for the Subnet Manager service (`sm_priority` 10 and 5).

### Recovery
If the cluster enters a split-brain state or catastrophic failure (as seen on 2026-01-21):
1.  **Soft Reset:** Run `reset.yml` to remove software.
2.  **Hard Reset:** Use `reboot_k3s_nodes.sh` (leveraging IPMI) to physically power cycle nodes that are unresponsive to SSH.
3.  **Rebuild:** Run `site.yml`.

### Useful Commands
**Check Node Status:**
```bash
kubectl get nodes -o wide
# Check just masters
kubectl get nodes -l "node-role.kubernetes.io/control-plane=true"
```

**Check Taints:**
```bash
kubectl describe node marconi3 | grep Taints
```
