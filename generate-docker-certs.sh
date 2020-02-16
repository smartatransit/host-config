#!/bin/bash
set +xe

# make sure you set the following variables:
#  OPENSSLPASS is the passphrase to be used for the produced
#  HOSTNAME is the hostname of the Docker host being configured

sudo openssl genrsa -passout "pass:$OPENSSLPASS" -aes256 -out /etc/docker/ssl/ca-key.pem 4096
sudo openssl req -passin "pass:$OPENSSLPASS" -subj "/CN=$HOSTNAME" -new -x509 -days 365 -key /etc/docker/ssl/ca-key.pem -sha256 -out /etc/docker/ssl/ca.pem

##############
sudo openssl genrsa -out /etc/docker/ssl/server-key.pem 4096

sudo openssl req -subj "/CN=$HOSTNAME" -sha256 -new -key /etc/docker/ssl/server-key.pem -out server.csr

echo subjectAltName = DNS:$HOSTNAME,IP:209.59.191.70,IP:10.33.58.100,IP:127.0.0.1 >> extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf
sudo openssl x509 -passin "pass:$OPENSSLPASS" -req -days 365 -sha256 -in server.csr -CA /etc/docker/ssl/ca.pem -CAkey /etc/docker/ssl/ca-key.pem -CAcreateserial -out /etc/docker/ssl/server-cert.pem -extfile extfile.cnf

##############
sudo openssl genrsa -out key.pem 4096

sudo openssl req -subj '/CN=client' -new -key key.pem -out client.csr

echo extendedKeyUsage = clientAuth > extfile-client.cnf
sudo openssl x509 -passin "pass:$OPENSSLPASS" -req -days 365 -sha256 -in client.csr -CA /etc/docker/ssl/ca.pem -CAkey /etc/docker/ssl/ca-key.pem -CAcreateserial -out /etc/docker/ssl/cert.pem -extfile extfile-client.cnf

rm -fv client.csr server.csr extfile.cnf extfile-client.cnf
sudo chmod -v 0400 /etc/docker/ssl/ca-key.pem key.pem /etc/docker/ssl/server-key.pem
sudo chmod -v 0444 /etc/docker/ssl/ca.pem /etc/docker/ssl/server-cert.pem /etc/docker/ssl/cert.pem

echo '{
  "tls": true,
  "tlscacert": "/etc/docker/ssl/ca.pem",
  "tlscert": "/etc/docker/ssl/server-cert.pem",
  "tlskey": "/etc/docker/ssl/server-key.pem",
  "tlsverify": true
}' | sudo tee /etc/docker/daemon.json

# Configuring systemd socket to listen on TCP
# https://github.com/docker/docker/issues/25471#issuecomment-238076313
sudo mkdir -p /etc/systemd/system/docker.socket.d
echo '[Socket]
ListenStream= # If you want to disable default unix socket
ListenStream=0.0.0.0:2376' | sudo tee /etc/systemd/system/docker.socket.d/tcp_secure.conf
sudo systemctl daemon-reload
sudo service docker restart
