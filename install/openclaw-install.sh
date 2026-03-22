#!/usr/bin/env bash

# Copyright (c) 2026 community-scripts ORG
# Author: Seb James
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openclaw.ai/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

REQUIRED_NODE_MAJOR="${REQUIRED_NODE_MAJOR:-24}"
FALLBACK_NODE_MAJOR="${FALLBACK_NODE_MAJOR:-22}"

msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Installed Dependencies"

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
  if ! $STD bash "$NODESOURCE_TMP"; then
    cleanup_nodesource_tmp
    msg_error "Node.js ${REQUIRED_NODE_MAJOR} setup script failed"
    exit 1
  fi
elif try_nodesource_setup "$FALLBACK_NODE_MAJOR"; then
  msg_warn "Node.js ${REQUIRED_NODE_MAJOR} unavailable for this distro, falling back to ${FALLBACK_NODE_MAJOR}"
  if ! $STD bash "$NODESOURCE_TMP"; then
    cleanup_nodesource_tmp
    msg_error "Node.js ${FALLBACK_NODE_MAJOR} setup script failed"
    exit 1
  fi
else
  msg_error "Neither Node.js ${REQUIRED_NODE_MAJOR} nor ${FALLBACK_NODE_MAJOR} available via NodeSource"
  exit 1
fi
cleanup_nodesource_tmp
$STD apt install -y nodejs
if ! command -v node &>/dev/null || ! node --version &>/dev/null; then
  msg_error "Node.js installation failed"
  exit 1
fi
msg_ok "Installed Node.js $(node --version)"

msg_info "Installing OpenClaw"
$STD npm install -g openclaw
if ! command -v openclaw &>/dev/null || ! openclaw --version &>/dev/null; then
  msg_error "OpenClaw installation failed"
  exit 1
fi
msg_ok "Installed OpenClaw $(openclaw --version)"

motd_ssh
customize
cleanup_lxc
