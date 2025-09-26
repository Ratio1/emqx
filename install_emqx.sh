#!/bin/bash

#copy certs
cp ./emqx_cert.crt /opt/emqx/etc/certs
cp ./emqx_cert.key /opt/emqx/etc/certs
cp ./emqx_cert.crt /opt/emqx/etc/certs/cert.pem
cp ./emqx_cert.key /opt/emqx/etc/certs/key.pem

#ensure log dir exists and is writeable
mkdir /opt/emqx/log
chmod 777 /opt/emqx/log


# install_emqx.sh
cp ./emqx.service /etc/systemd/system/emqx.service
systemctl daemon-reload
systemctl enable emqx
systemctl start emqx
systemctl status emqx --no-pager -l