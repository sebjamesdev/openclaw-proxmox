#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2026 community-scripts ORG
# Author: Seb James
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openclaw.ai/

APP="OpenClaw"
REQUIRED_NODE_MAJOR=24
FALLBACK_NODE_MAJOR=22
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-11}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

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

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v openclaw &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  CURRENT_NODE=$(node -v | cut -d. -f1 | tr -d 'v')
  if [[ "$CURRENT_NODE" -lt "$FALLBACK_NODE_MAJOR" ]]; then
    msg_info "Upgrading Node.js from v${CURRENT_NODE} to v${REQUIRED_NODE_MAJOR}"
    if try_nodesource_setup "$REQUIRED_NODE_MAJOR"; then
      if ! $STD bash "$NODESOURCE_TMP"; then
        cleanup_nodesource_tmp
        msg_error "Node.js ${REQUIRED_NODE_MAJOR} setup script failed"
        exit 1
      fi
    elif try_nodesource_setup "$FALLBACK_NODE_MAJOR"; then
      msg_warn "Node.js ${REQUIRED_NODE_MAJOR} unavailable, falling back to ${FALLBACK_NODE_MAJOR}"
      if ! $STD bash "$NODESOURCE_TMP"; then
        cleanup_nodesource_tmp
        msg_error "Node.js ${FALLBACK_NODE_MAJOR} setup script failed"
        exit 1
      fi
    else
      msg_error "Node.js upgrade failed — NodeSource unavailable"
      exit 1
    fi
    cleanup_nodesource_tmp
    $STD apt install -y nodejs
    if [[ $(node -v | cut -d. -f1 | tr -d 'v') -lt $FALLBACK_NODE_MAJOR ]]; then
      msg_error "Node.js upgrade failed"
      exit 1
    fi
    $STD npm rebuild
    msg_ok "Upgraded Node.js to $(node --version)"
  fi

  msg_info "Updating ${APP}"
  if ! $STD openclaw update; then
    msg_error "OpenClaw update failed — check logs with 'journalctl -u openclaw'"
    exit 1
  fi
  msg_ok "Updated ${APP}"

  msg_info "Verifying Gateway Health"
  if openclaw health &>/dev/null; then
    msg_ok "Gateway is healthy"
  else
    msg_warn "Gateway health check failed — the gateway may need manual attention. Run 'openclaw daemon status' for details."
  fi

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} has been installed but the gateway is NOT running yet.${CL}"
echo -e "${INFO}${YW} Run the following command inside the container to complete setup:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}openclaw onboard --install-daemon${CL}"
echo -e "${INFO}${YW} Once onboarding is complete, access the dashboard at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:18789${CL}"
echo -e "${INFO}${YW} Ensure port 18789 is accessible if connecting from another network.${CL}"
