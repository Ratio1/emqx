#!/bin/bash

#copy certs
cp ./emqx_cert.crt /opt/emqx/etc/certs
cp ./emqx_cert.key /opt/emqx/etc/certs

# install_emqx.sh
cp ./emqx.service /etc/systemd/system/emqx.service
systemctl daemon-reload
systemctl enable emqx
systemctl start emqx
systemctl status emqx --no-pager -l