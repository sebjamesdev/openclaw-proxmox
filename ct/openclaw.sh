#!/usr/bin/env bash

# Copyright (c) 2026 Seb James
# License: MIT
# Source: https://openclaw.ai/

set -Eeuo pipefail

REPO="https://raw.githubusercontent.com/sebjamesdev/openclaw-proxmox/main"
APP="OpenClaw"

# ── Defaults ──────────────────────────────────────────────────────────────────
CT_ID="${CT_ID:-}"
HOSTNAME="${CT_HOSTNAME:-openclaw}"
DISK_SIZE="${DISK_SIZE:-10}"
CPU_CORES="${CPU_CORES:-2}"
RAM="${RAM:-4096}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
OS_TYPE="${OS_TYPE:-debian}"
OS_VERSION="${OS_VERSION:-12}"
NET="${NET:-dhcp}"
UNPRIVILEGED="${UNPRIVILEGED:-1}"

# ── Colours ───────────────────────────────────────────────────────────────────
GN='\033[1;92m'
RD='\033[01;31m'
YW='\033[33m'
CL='\033[m'
BFR="\\r\\033[K"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
INFO="  ${YW}➜${CL}"

function msg_info() { echo -ne "  ${YW}⏳ $1...${CL}"; }
function msg_ok()   { echo -e "${BFR}  ${CM} ${GN}$1${CL}"; }
function msg_error() { echo -e "${BFR}  ${CROSS} ${RD}$1${CL}"; }

# ── Header ────────────────────────────────────────────────────────────────────
echo -e "\n${GN}╔═══════════════════════════════════════════════╗${CL}"
echo -e "${GN}║         ${YW}${APP} LXC Container Installer${GN}         ║${CL}"
echo -e "${GN}╚═══════════════════════════════════════════════╝${CL}\n"

# ── Checks ────────────────────────────────────────────────────────────────────
if ! command -v pct &>/dev/null; then
  msg_error "This script must be run on a Proxmox VE host (pct not found)"
  exit 1
fi

if [[ $(id -u) -ne 0 ]]; then
  msg_error "This script must be run as root"
  exit 1
fi

# ── Auto-select next available CT ID ──────────────────────────────────────────
if [[ -z "$CT_ID" ]]; then
  CT_ID=$(pvesh get /cluster/nextid)
fi

# ── Download template ─────────────────────────────────────────────────────────
TEMPLATE="${OS_TYPE}-${OS_VERSION}-standard"
TEMPLATE_FILE=$(pveam available --section system | grep "$TEMPLATE" | sort -t- -k2 -V | tail -n1 | awk '{print $2}')

if [[ -z "$TEMPLATE_FILE" ]]; then
  msg_error "Could not find template matching '${TEMPLATE}'"
  exit 1
fi

if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE_FILE"; then
  msg_info "Downloading template ${TEMPLATE_FILE}"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_FILE" &>/dev/null
  msg_ok "Downloaded template"
else
  msg_ok "Template already available"
fi

# ── Build network string ─────────────────────────────────────────────────────
NET_STRING="name=eth0,bridge=${BRIDGE}"
if [[ "$NET" == "dhcp" ]]; then
  NET_STRING+=",ip=dhcp"
else
  NET_STRING+=",ip=${NET}"
fi

# ── Create container ──────────────────────────────────────────────────────────
msg_info "Creating LXC container (ID: ${CT_ID})"
pct create "$CT_ID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_FILE}" \
  --hostname "$HOSTNAME" \
  --cores "$CPU_CORES" \
  --memory "$RAM" \
  --net0 "$NET_STRING" \
  --rootfs "${STORAGE}:${DISK_SIZE}" \
  --unprivileged "$UNPRIVILEGED" \
  --features nesting=1 \
  --onboot 1 \
  --start 0 &>/dev/null
msg_ok "Created container ${CT_ID}"

# ── Start container ──────────────────────────────────────────────────────────
msg_info "Starting container"
pct start "$CT_ID"
sleep 3

# Wait for network
msg_info "Waiting for network"
for i in $(seq 1 30); do
  if lxc-attach -n "$CT_ID" -- ping -c1 -W1 1.1.1.1 &>/dev/null; then
    break
  fi
  sleep 1
done
msg_ok "Network is up"

# ── Run install script inside container ──────────────────────────────────────
msg_info "Running install script inside container"
lxc-attach -n "$CT_ID" -- bash -c "$(curl -fsSL ${REPO}/install/openclaw-install.sh)"
msg_ok "Install script completed"

# ── Get container IP ──────────────────────────────────────────────────────────
IP=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
msg_ok "Completed successfully!"
echo ""
echo -e "${INFO} ${GN}${APP} has been installed but the gateway is NOT running yet.${CL}"
echo -e "${INFO} Run the following command inside the container to complete setup:"
echo -e "      ${GN}pct exec ${CT_ID} -- openclaw onboard --install-daemon${CL}"
echo -e "${INFO} Once onboarding is complete, access the dashboard at:"
echo -e "      ${GN}http://${IP}:18789${CL}"
echo -e "${INFO} Ensure port 18789 is accessible if connecting from another network."
echo ""
