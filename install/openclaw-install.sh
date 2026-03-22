#!/usr/bin/env bash

# Copyright (c) 2026 Seb James
# License: MIT
# Source: https://openclaw.ai/
#
# This script runs INSIDE the LXC container.

set -Eeuo pipefail

REQUIRED_NODE_MAJOR="${REQUIRED_NODE_MAJOR:-24}"
FALLBACK_NODE_MAJOR="${FALLBACK_NODE_MAJOR:-22}"

# ── Colours ───────────────────────────────────────────────────────────────────
GN='\033[1;92m'
RD='\033[01;31m'
YW='\033[33m'
CL='\033[m'
BFR="\\r\\033[K"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

function msg_info()  { echo -ne "  ${YW}⏳ $1...${CL}"; }
function msg_ok()    { echo -e "${BFR}  ${CM} ${GN}$1${CL}"; }
function msg_warn()  { echo -e "${BFR}  ${YW}⚠  $1${CL}"; }
function msg_error() { echo -e "${BFR}  ${CROSS} ${RD}$1${CL}"; }

# ── OS Update ─────────────────────────────────────────────────────────────────
msg_info "Updating OS"
apt-get update -qq &>/dev/null
apt-get -y upgrade &>/dev/null
msg_ok "Updated OS"

# ── Dependencies ──────────────────────────────────────────────────────────────
msg_info "Installing dependencies"
apt-get install -y curl sudo build-essential &>/dev/null
msg_ok "Installed dependencies"

# ── Node.js ───────────────────────────────────────────────────────────────────
NODESOURCE_TMP=""

function cleanup_nodesource_tmp() {
  [[ -n "$NODESOURCE_TMP" ]] && rm -f "$NODESOURCE_TMP"
}

function try_nodesource_setup() {
  local version="$1"
  local setup_url="https://deb.nodesource.com/setup_${version}.x"

  NODESOURCE_TMP="$(mktemp /tmp/nodesource_setup.XXXXXX)"

  if ! curl -fsSL --max-time 30 -o "$NODESOURCE_TMP" "$setup_url"; then
    cleanup_nodesource_tmp
    return 1
  fi

  if grep -qi -e "unsupported" -e "not currently supported" -e "is not supported" "$NODESOURCE_TMP"; then
    cleanup_nodesource_tmp
    return 1
  fi

  return 0
}

msg_info "Installing Node.js ${REQUIRED_NODE_MAJOR}"
if try_nodesource_setup "$REQUIRED_NODE_MAJOR"; then
  if ! bash "$NODESOURCE_TMP" &>/dev/null; then
    cleanup_nodesource_tmp
    msg_error "Node.js ${REQUIRED_NODE_MAJOR} setup script failed"
    exit 1
  fi
elif try_nodesource_setup "$FALLBACK_NODE_MAJOR"; then
  msg_warn "Node.js ${REQUIRED_NODE_MAJOR} unavailable for this distro, falling back to ${FALLBACK_NODE_MAJOR}"
  if ! bash "$NODESOURCE_TMP" &>/dev/null; then
    cleanup_nodesource_tmp
    msg_error "Node.js ${FALLBACK_NODE_MAJOR} setup script failed"
    exit 1
  fi
else
  msg_error "Neither Node.js ${REQUIRED_NODE_MAJOR} nor ${FALLBACK_NODE_MAJOR} available via NodeSource"
  exit 1
fi
cleanup_nodesource_tmp

apt-get install -y nodejs &>/dev/null
if ! command -v node &>/dev/null || ! node --version &>/dev/null; then
  msg_error "Node.js installation failed"
  exit 1
fi
msg_ok "Installed Node.js $(node --version)"

# ── OpenClaw ──────────────────────────────────────────────────────────────────
msg_info "Installing OpenClaw"
npm install -g openclaw &>/dev/null
if ! command -v openclaw &>/dev/null || ! openclaw --version &>/dev/null; then
  msg_error "OpenClaw installation failed"
  exit 1
fi
msg_ok "Installed OpenClaw $(openclaw --version)"

# ── Cleanup ───────────────────────────────────────────────────────────────────
msg_info "Cleaning up"
apt-get -y autoremove &>/dev/null
apt-get -y autoclean &>/dev/null
msg_ok "Cleaned up"
