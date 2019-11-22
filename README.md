# host-config
A living log of all system-level changes made to the kubernetes host, for reproducibility

1. Starting from:
```
Distributor ID:	Ubuntu
Description:	Ubuntu 18.04.3 LTS
Release:	18.04
Codename:	bionic
```
2. Create an `admin` user with sudo priveleges, and give it an authorized key
https://www.digitalocean.com/community/tutorials/how-to-create-a-sudo-user-on-ubuntu-quickstart
3. Turn off password authentication
https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server
**NOTE:** Make sure you test the sudo priveleges first! If you turn off password authentication in `sshd` and your `admin` user is unable to gain root access, _you are screwed_.
4. Flush `iptables` (`sudo iptables -F`) and then installing and use `ufw`. Make sure you expose port 22 before enabling the firewall. This is so we can easily expose 2376 for the docker socket later, but it needs to be done now since otherwise we'll destroy the Docker chains when we flush `iptables`.
5. Install docker
https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-engine---community-1
6. Securely expose the docker socket
https://docs.docker.com/engine/security/https/
Use this to generate the certificates you need: (you'll need a passphrase, which you'll need to enter at various points)
```
sudo openssl genrsa -aes256 -out /etc/docker/ssl/ca-key.pem 4096
sudo openssl req -new -x509 -days 365 -key /etc/docker/ssl/ca-key.pem -sha256 -out /etc/docker/ssl/ca.pem

##############
sudo openssl genrsa -out /etc/docker/ssl/server-key.pem 4096

sudo openssl req -subj "/CN=smarta-data.ataper.net" -sha256 -new -key /etc/docker/ssl/server-key.pem -out server.csr

echo subjectAltName = DNS:smarta-data.ataper.net,IP:209.59.191.70,IP:10.33.58.100,IP:127.0.0.1 >> extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf
sudo openssl x509 -req -days 365 -sha256 -in server.csr -CA /etc/docker/ssl/ca.pem -CAkey /etc/docker/ssl/ca-key.pem -CAcreateserial -out /etc/docker/ssl/server-cert.pem -extfile extfile.cnf

##############
sudo openssl genrsa -out key.pem 4096

sudo openssl req -subj '/CN=client' -new -key key.pem -out client.csr

echo extendedKeyUsage = clientAuth > extfile-client.cnf
sudo openssl x509 -req -days 365 -sha256 -in client.csr -CA /etc/docker/ssl/ca.pem -CAkey /etc/docker/ssl/ca-key.pem -CAcreateserial -out /etc/docker/ssl/cert.pem -extfile extfile-client.cnf

rm -v client.csr server.csr extfile.cnf extfile-client.cnf
sudo chmod -v 0400 /etc/docker/ssl/ca-key.pem key.pem /etc/docker/ssl/server-key.pem
sudo chmod -v 0444 /etc/docker/ssl/ca.pem /etc/docker/ssl/server-cert.pem /etc/docker/ssl/cert.pem
```
Store all the certs in `/etc/docker/ssl` rather than the current directory like in the tutorial, then use this to configure and restart the docker:
```
#!/bin/bash
# Configuring Docker to use TLS with systemd socket
# https://docs.docker.com/engine/reference/commandline/dockerd//#daemon-configuration-file

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
```
Test locally by copying over `ca.pem` as well as `key.pem` and `cert.pem`:
```
docker \
   --host tcp://smarta-data.ataper.net:2376 \
   --tlsverify \
   --tlscacert=ca.pem \
   --tlscert=cert.pem \
   --tlskey=key.pem \
   container ls
```
7. Create a terraform user and give it SSH access but NOT sudo powers:
```
mkdir -p /home/terraform/.ssh
mkdir -p /home/terraform/data
touch /home/terraform/.ssh/authorized_keys
useradd -d /home/terraform terraform
chown -R terraform:terraform /home/terraform/
chmod 700 /home/terraform/.ssh
chmod 644 /home/terraform/.ssh/authorized_keys
```
Now generate a key-pair locally. Provide the public end to the `authorized_keys` file you just created, and the private end (and username) to our Terraform Cloud workspace.
8. Stop and disable the default Apache server to free up port 80 for other services:
```
sudo systemctl disable apache2
sudo systemctl stop apache2
```
