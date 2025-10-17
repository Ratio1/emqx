#!/bin/bash

if [ ! -f /opt/emqx/etc/emqx.conf ]; then
  mkdir -p /opt/emqx
  docker create --name emqx-seed emqx/emqx:5.8.7
  docker cp emqx-seed:/opt/emqx/etc /opt/emqx/
  docker rm emqx-seed
fi

#copy cert
cp ./emqx_cert.crt /opt/emqx/etc/certs
cp ./emqx_cert.key /opt/emqx/etc/certs
cp ./emqx_cert.crt /opt/emqx/etc/certs/cert.pem
cp ./emqx_cert.key /opt/emqx/etc/certs/key.pem

#ensure log dir exists and is writeable
mkdir -p /opt/emqx/log
chmod 777 /opt/emqx/log
mkdir -p /opt/emqx/data
chmod 777 /opt/emqx/data

# Make a random API key/secret (printable)
API_KEY=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 16)
API_SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48)

mkdir -p /opt/emqx/etc
cat >/opt/emqx/etc/default_api_key.conf <<EOF
${API_KEY}:${API_SECRET}:administrator
EOF

# HOCON snippet to point to the bootstrap file
cat >>/opt/emqx/etc/base.hocon <<EOF
listeners.ssl.default.enable_authn = quick_deny_anonymous
api_key = { bootstrap_file = "/opt/emqx/etc/default_api_key.conf" }
EOF


# install_emqx.sh
cp ./emqx.service /etc/systemd/system/emqx.service
systemctl daemon-reload
systemctl enable emqx
systemctl start emqx
systemctl status emqx --no-pager -l

#verify emqx docker ip address and update nginx config accordingly
EMQX_DOCKER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' emqx)
sed -i "s/proxy_pass http:\/\/172.17.0.2:18083;/proxy_pass http:\/\/${EMQX_DOCKER_IP}:18083;/g" /etc/nginx/sites-available/emqx.conf     
systemctl reload nginx