#!/usr/bin/env bash
# emqx-pull.sh
# Copy EMQX /opt/emqx/data and /opt/emqx/etc from a remote SSH host to localhost.
# Usage: ./emqx-pull.sh user@host
#
# Notes:
# - Requires: ssh, rsync
# - Destination: /opt/emqx/migration/<host>_<timestamp>/{data,etc}
# - Does NOT overwrite your live /opt/emqx/{data,etc}. You can promote the snapshot later.

set -Eeuo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }

# --- Pre-flight
command -v ssh >/dev/null 2>&1 || die "ssh not found"
command -v rsync >/dev/null 2>&1 || die "rsync not found"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 user@host"
  exit 1
fi

SRC="$1"
SRC_HOST="${SRC#*@}"              # extract host/ip for folder naming
TS="$(date +%Y%m%d_%H%M%S)"
DEST_BASE="/opt/emqx"
LOCAL_SUDO=""
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  LOCAL_SUDO="sudo"
fi

REMOTE_DATA="/opt/emqx/data"
REMOTE_ETC="/opt/emqx/etc"

# Accept new host keys automatically; keep strict for existing ones
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new"

# --- Validate remote paths
info "Checking remote paths on ${SRC} ..."
ssh ${SSH_OPTS} "${SRC}" "test -d '${REMOTE_DATA}'" \
  || die "Remote path missing: ${REMOTE_DATA}"
ssh ${SSH_OPTS} "${SRC}" "test -d '${REMOTE_ETC}'" \
  || die "Remote path missing: ${REMOTE_ETC}"

# --- Prepare local destination
info "Creating local destination: ${DEST_BASE}"
${LOCAL_SUDO} mkdir -p "${DEST_BASE}/data" "${DEST_BASE}/etc"

# --- Copy (rsync preserves perms/ownerships; add -z for compression if links are slow)
# Using -aHAX:
#  -a archive (perms, times, owner, group, devices)
#  -H hard links
#  -A ACLs
#  -X xattrs
#  -P progress+partial (resume-friendly)
RSYNC_COMMON_OPTS="-aHAXP --numeric-ids --inplace --delete-after -e 'ssh ${SSH_OPTS}'"

info "Syncing ${REMOTE_DATA} -> ${DEST_BASE}/data ..."
eval rsync ${RSYNC_COMMON_OPTS} "'${SRC}:${REMOTE_DATA}/'" "'${DEST_BASE}/data/'"

info "Syncing ${REMOTE_ETC} -> ${DEST_BASE}/etc ..."
eval rsync ${RSYNC_COMMON_OPTS} "'${SRC}:${REMOTE_ETC}/'" "'${DEST_BASE}/etc/'"

# --- Sanity summaries
info "Local snapshot created at: ${DEST_BASE}"
${LOCAL_SUDO} du -sh "${DEST_BASE}/data" "${DEST_BASE}/etc" | sed 's/^/[SIZE] /'

