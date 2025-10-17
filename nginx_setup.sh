#!/usr/bin/env bash
# ipfs-nginx-setup.sh â€” secure nginx reverse-proxy for Kubo 0.35 API
# Usage: sudo ./ipfs-nginx-setup.sh [SERVER_IP] [USER] [PASS]
set -euo pipefail

### ---- 1. Vars & helpers -------------------------------------------------
SERVER_IP="${1:-$(ip route get 1.1.1.1 | awk '{print $7; exit}')}"  # pick first routed IPv4 :contentReference[oaicite:0]{index=0}


# Certificate filenames
LOCAL_CRT="$PWD/emqx_cert.crt"
LOCAL_KEY="$PWD/emqx_cert.key"
CERT_DIR=/etc/ssl/certs
KEY_DIR=/etc/ssl/private
SYS_CRT="$CERT_DIR/emqx_cert.crt"
SYS_KEY="$KEY_DIR/emqx_cert.key"

SITE=/etc/nginx/sites-available/emqx.conf

echo "==> Using public IP  $SERVER_IP"

### ---- 2. Install packages ----------------------------------------------
apt-get update -qq
apt-get install -y nginx openssl apache2-utils  # htpasswd lives here :contentReference[oaicite:1]{index=1}

# ---- Kill the port-80 ï¿½defaultï¿½ listener -------------------------------
rm -f /etc/nginx/sites-enabled/default

### ---- 3. Generate self-signed certificate -------------------------------
if [[ ! -f "$LOCAL_CRT" || ! -f "$LOCAL_KEY" ]]; then
  echo "==> Generating self-signed TLS certificate in $PWD ï¿½"
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
          -subj "/CN=${SERVER_IP}" \
          -addext "subjectAltName = DNS:${SERVER_IP},IP:${SERVER_IP}" \
          -keyout "$LOCAL_KEY" -out "$LOCAL_CRT"
else
  echo "==> Re-using existing $LOCAL_CRT and $LOCAL_KEY"
fi
install -Dm600 "$LOCAL_CRT" "$SYS_CRT"
install -Dm600 "$LOCAL_KEY" "$SYS_KEY"
echo "==> Installed certificate to $SYS_CRT"
echo "==> Installed key         to $SYS_KEY"



### ---- 5. Write nginx vhost ---------------------------------------------
cat >"$SITE"<<EOF
server {
    listen ${SERVER_IP}:8443 ssl http2;
    # --- TLS ----------------------------------------------------------------
    ssl_certificate     $SYS_CRT;
    ssl_certificate_key $SYS_KEY;
    ssl_protocols       TLSv1.3;                                        # TLS 1.3 only :contentReference[oaicite:4]{index=4}
    ssl_conf_command    Ciphersuites TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256;
    add_header Strict-Transport-Security "max-age=31536000" always;

    location /               {  proxy_pass http://172.17.0.2:18083; }
}
EOF

ln -s "$SITE" /etc/nginx/sites-enabled/ 2>/dev/null || true

### ---- 6. Harden & reload -------------------------------------------------
nginx -t                                              # syntax check :contentReference[oaicite:7]{index=7}
systemctl reload nginx
echo "==> nginx is now serving https://${SERVER_IP}"
