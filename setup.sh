#!/bin/sh
set -e

if [ -z ${PRIMARY_USER+x} ]; then echo "PRIMARY_USER must be set"; exit; fi
if [ -z ${OPENSSLPASS+x} ]; then echo "OPENSSLPASS must be set"; exit; fi
if [ -z ${HOSTNAME+x} ]; then echo "HOSTNAME must be set"; exit; fi
if [ -z ${EXTERNAL_IP+x} ]; then echo "EXTERNAL_IP must be set"; exit; fi
if [ -z ${INTERNAL_IP+x} ]; then echo "INTERNAL_IP must be set"; exit; fi

apt update
apt install -y curl

### install docker ###
if ! type docker > /dev/null; then
  # install foobar here
  echo "installing docker"
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
fi

echo usermod -aG docker $PRIMARY_USER
usermod -aG docker $PRIMARY_USER

### generate certs for docker ###
mkdir -p /etc/docker/ssl

openssl genrsa -passout "pass:$OPENSSLPASS" -aes256 -out /etc/docker/ssl/ca-key.pem 4096
openssl req -passin "pass:$OPENSSLPASS" -subj "/CN=$HOSTNAME" -new -x509 -days 365 -key /etc/docker/ssl/ca-key.pem -sha256 -out /etc/docker/ssl/ca.pem

##############
openssl genrsa -out /etc/docker/ssl/server-key.pem 4096

openssl req -subj "/CN=$HOSTNAME" -sha256 -new -key /etc/docker/ssl/server-key.pem -out server.csr

echo subjectAltName = DNS:$HOSTNAME,DNS:localhost,IP:$EXTERNAL_IP,IP:$INTERNAL_IP,IP:127.0.0.1 >> extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf
openssl x509 -passin "pass:$OPENSSLPASS" -req -days 365 -sha256 -in server.csr -CA /etc/docker/ssl/ca.pem -CAkey /etc/docker/ssl/ca-key.pem -CAcreateserial -out /etc/docker/ssl/server-cert.pem -extfile extfile.cnf

##############
openssl genrsa -out key.pem 4096

openssl req -subj '/CN=client' -new -key key.pem -out client.csr

echo extendedKeyUsage = clientAuth > extfile-client.cnf
openssl x509 -passin "pass:$OPENSSLPASS" -req -days 365 -sha256 -in client.csr -CA /etc/docker/ssl/ca.pem -CAkey /etc/docker/ssl/ca-key.pem -CAcreateserial -out /etc/docker/ssl/cert.pem -extfile extfile-client.cnf

rm -fv client.csr server.csr extfile.cnf extfile-client.cnf
chmod -v 0400 /etc/docker/ssl/ca-key.pem key.pem /etc/docker/ssl/server-key.pem
chmod -v 0444 /etc/docker/ssl/ca.pem /etc/docker/ssl/server-cert.pem /etc/docker/ssl/cert.pem

### configure and restart docker ###
echo '{
  "tls": true,
  "tlscacert": "/etc/docker/ssl/ca.pem",
  "tlscert": "/etc/docker/ssl/server-cert.pem",
  "tlskey": "/etc/docker/ssl/server-key.pem",
  "tlsverify": true
}' | tee /etc/docker/daemon.json

# Configuring systemd socket to listen on TCP
# https://github.com/docker/docker/issues/25471#issuecomment-238076313
mkdir -p /etc/systemd/system/docker.socket.d
echo '[Socket]
ListenStream= # If you want to disable default unix socket
ListenStream=0.0.0.0:2376' | tee /etc/systemd/system/docker.socket.d/tcp_secure.conf
systemctl daemon-reload
service docker restart

### test the connections ###
mkdir -p dockerssl
cp /etc/docker/ssl/ca.pem /etc/docker/ssl/cert.pem dockerssl/
mv key.pem dockerssl/

docker \
   --host tcp://localhost:2376 \
   --tlsverify \
   --tlscacert=dockerssl/ca.pem \
   --tlscert=dockerssl/cert.pem \
   --tlskey=dockerssl/key.pem \
   container ls

### set up the terraform user ###
mkdir -p /home/terraform/.ssh
mkdir -p /home/terraform/data
touch /home/terraform/.ssh/authorized_keys
useradd -d /home/terraform terraform || echo "User terraform already exists."
chown -R terraform:terraform /home/terraform/
chmod 700 /home/terraform/.ssh
chmod 644 /home/terraform/.ssh/authorized_keys
