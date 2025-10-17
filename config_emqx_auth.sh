#!/usr/bin/env bash
# emqx_bootstrap_auth.sh
# Create API key, enable built_in_database authenticator, and create/update a user.
# Usage:
#   ./config_emqxauth.sh -c emqx -u myuser -p s3cr3t
# Defaults:
#   container=emqx

set -euo pipefail

# ---- defaults ----
CONTAINER="emqx"
USER_ID="ratio1"
PASSWORD=""
USER_ID_TYPE="username"

# ---- args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--container) CONTAINER="$2"; shift 2 ;;
    -u|--user) USER_ID="$2"; shift 2 ;;
    -p|--password) PASSWORD="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,50p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$USER_ID" || -z "$PASSWORD" ]]; then
  echo "ERROR: --user and --password are required." >&2
  exit 1
fi

# ---- helpers ----
die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
need docker

# Ensure container is running
docker inspect -f '{{.State.Running}}' "$CONTAINER" >/dev/null 2>&1 || die "Container '$CONTAINER' not found or not running."

#read API key/secret from /opt/emqx/etc/default_api_key.conf
API_CRED=$(sh -c "cat /opt/emqx/etc/default_api_key.conf" | tr -d '\r\n')
KEY=$(echo "$API_CRED" | cut -d: -f1)
SECRET=$(echo "$API_CRED" | cut -d: -f2)

AUTH_JSON=$(cat <<JSON
{
  "mechanism": "password_based",
  "backend": "built_in_database",
  "user_id_type": "username",
  "password_hash_algorithm": {
    "name": "sha256"
  }
}
JSON
)

EMQX_DOCKER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${CONTAINER})

# URL-encoded ID for authenticator: "password_based:built_in_database" -> "password_based%3Abuilt_in_database"
AUTH_URL="http://${EMQX_DOCKER_IP}:18083/api/v5/authentication"
curl -sS -u "${KEY}:${SECRET}" -X POST "${AUTH_URL}" -H 'Content-Type: application/json' -d "${AUTH_JSON}"
echo "   Authenticator applied."

# Create or update user
USERS_BASE="http://${EMQX_DOCKER_IP}:18083/api/v5/authentication/password_based%3Abuilt_in_database/users"
CREATE_PAYLOAD=$(cat <<JSON
{"user_id":"${USER_ID}","password":"${PASSWORD}","is_superuser":"false"}
JSON
)

echo ">> Creating or updating user '${USER_ID}'..."
set +e
curl -s -o /dev/null -w '%{http_code}' -u '${KEY}:${SECRET}' '${USERS_BASE}/${USER_ID}' | {
  read -r CODE
  set -e
  if [[ "$CODE" = "200" ]]; then
    echo "   User exists; updating password/superuser flag."
    curl -sS -u "${KEY}:${SECRET}" -X PUT "${USERS_BASE}/${USER_ID}" -H 'Content-Type: application/json' -d "${CREATE_PAYLOAD}"
    echo
  else
    echo "   Creating user."
    curl -sS -u "${KEY}:${SECRET}" -X POST "${USERS_BASE}" -H 'Content-Type: application/json' -d "${CREATE_PAYLOAD}"

    echo
  fi
}
echo "? Done."
echo "   MQTT can now authenticate with: -u '${USER_ID}' -P '<your password>'"
