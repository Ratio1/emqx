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

# Inside-container runner
run_in() {
  docker exec -i "$CONTAINER" sh -lc "$*"
}

# Ensure we can talk HTTP inside the container: need curl or wget
ensure_http_client() {
  if run_in 'command -v curl >/dev/null 2>&1'; then
    echo "curl"
    return
  fi
  if run_in 'command -v wget >/dev/null 2>&1'; then
    echo "wget"
    return
  fi

  echo "No curl/wget in container. Trying to install curl..." >&2
  # Try common package managers. Some images are minimal; if none work, we bail out.
  if run_in 'command -v apk >/dev/null 2>&1'; then
    run_in 'apk add --no-cache curl' || die "Failed to install curl via apk"
  elif run_in 'command -v apt-get >/dev/null 2>&1'; then
    run_in 'apt-get update && apt-get install -y curl' || die "Failed to install curl via apt-get"
  elif run_in 'command -v dnf >/dev/null 2>&1'; then
    run_in 'dnf install -y curl' || die "Failed to install curl via dnf"
  elif run_in 'command -v yum >/dev/null 2>&1'; then
    run_in 'yum install -y curl' || die "Failed to install curl via yum"
  else
    die "No package manager found in container; install curl manually or expose 18083 and re-run."
  fi
  echo "curl"
}

HTTP_CLIENT=$(ensure_http_client)

# Create API key
echo ">> Creating EMQX API key..."
API_OUT=$(run_in 'emqx ctl api-key create') || die "Failed to create API key"
# Expected output lines like:
# Key: xxxxxx
# Secret: yyyyyy
KEY=$(printf "%s\n" "$API_OUT" | awk '/^Key:/ {print $2}')
SECRET=$(printf "%s\n" "$API_OUT" | awk '/^Secret:/ {print $2}')
[[ -n "${KEY:-}" && -n "${SECRET:-}" ]] || die "Could not parse API key/secret from output:
$API_OUT"

echo "   Key: $KEY"
echo "   Secret: (hidden)"


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

# URL-encoded ID for authenticator: "password_based:built_in_database" -> "password_based%3Abuilt_in_database"
AUTH_URL='http://127.0.0.1:18083/api/v5/authentication/password_based%3Abuilt_in_database'

echo ">> Enabling built_in_database authenticator..."
if [[ "$HTTP_CLIENT" = "curl" ]]; then
  run_in "curl -sS -u '${KEY}:${SECRET}' -X PUT '${AUTH_URL}' -H 'Content-Type: application/json' -d '$(printf "%s" "$AUTH_JSON" | sed "s/'/'\"'\"'/g")'"
else
  # wget fallback
  TMP=$(mktemp)
  printf "%s" "$AUTH_JSON" > "$TMP"
  run_in "wget -q --method=PUT --header='Content-Type: application/json' --user='${KEY}' --password='${SECRET}' --body-file='-' -O - '${AUTH_URL}' < '$TMP'"
  rm -f "$TMP"
fi
echo
echo "   Authenticator applied."

# Create or update user
USERS_BASE='http://127.0.0.1:18083/api/v5/authentication/password_based%3Abuilt_in_database/users'
CREATE_PAYLOAD=$(cat <<JSON
{"user_id":"${USER_ID}","password":"${PASSWORD}","is_superuser":${IS_SUPERUSER}}
JSON
)

echo ">> Creating or updating user '${USER_ID}'..."
if [[ "$HTTP_CLIENT" = "curl" ]]; then
  # Try GET
  set +e
  run_in "curl -s -o /dev/null -w '%{http_code}' -u '${KEY}:${SECRET}' '${USERS_BASE}/${USER_ID}'" | {
    read -r CODE
    set -e
    if [[ "$CODE" = "200" ]]; then
      echo "   User exists; updating password/superuser flag."
      run_in "curl -sS -u '${KEY}:${SECRET}' -X PUT '${USERS_BASE}/${USER_ID}' -H 'Content-Type: application/json' -d '$(printf "%s" "$CREATE_PAYLOAD" | sed "s/'/'\"'\"'/g")'"
      echo
    else
      echo "   Creating user."
      run_in "curl -sS -u '${KEY}:${SECRET}' -X POST '${USERS_BASE}' -H 'Content-Type: application/json' -d '$(printf "%s" "$CREATE_PAYLOAD" | sed "s/'/'\"'\"'/g")'"
      echo
    fi
  }
else
  # wget path (no easy status parsing) – attempt GET; if it fails we POST, else PUT
  set +e
  run_in "wget -q --user='${KEY}' --password='${SECRET}' -O - '${USERS_BASE}/${USER_ID}' >/dev/null"
  EXISTS=$?
  set -e
  if [[ "$EXISTS" -eq 0 ]]; then
    echo "   User exists; updating..."
    TMP=$(mktemp); printf "%s" "$CREATE_PAYLOAD" > "$TMP"
    run_in "wget -q --method=PUT --header='Content-Type: application/json' --user='${KEY}' --password='${SECRET}' --body-file='-' -O - '${USERS_BASE}/${USER_ID}' < '$TMP'"
    rm -f "$TMP"
    echo
  else
    echo "   Creating user..."
    TMP=$(mktemp); printf "%s" "$CREATE_PAYLOAD" > "$TMP"
    run_in "wget -q --method=POST --header='Content-Type: application/json' --user='${KEY}' --password='${SECRET}' --body-file='-' -O - '${USERS_BASE}' < '$TMP'"
    rm -f "$TMP"
    echo
  fi
fi

echo "✅ Done."
echo "   MQTT can now authenticate with: -u '${USER_ID}' -P '<your password>'"
