# host-config
A living log of all system-level changes made to the kubernetes host, for reproducibility

1. Starting from:
```
Distributor ID:	Ubuntu
Description:	Ubuntu 18.04.3 LTS
Release:	18.04
Codename:	bionic
```
1. Create an `admin` user with sudo priveleges, and give it an authorized key
https://www.digitalocean.com/community/tutorials/how-to-create-a-sudo-user-on-ubuntu-quickstart
1. Turn off password authentication
https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server
**NOTE:** Make sure you test the sudo priveleges first! If you turn off password authentication in `sshd` and your `admin` user is unable to gain root access, _you are screwed_.
1. Install docker
https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-engine---community-1




1. Securely expose the docker socket
https://docs.docker.com/engine/security/https/









TODOTODOTODOTODOTODO: turn all this into a script maybe? or is that too opaque?



# TODO
These things need to be done to get up and running. As they're each done, the doer should add some detail on how exactly they were handled and migrate them to the above list
* Set up minikube and make sure `kubectl` can be used remotely and securely without occupying port 80, which we'll need for service ingress. From there we can set up a terraform repository so that kubernetes config can be updated from Git without directly accessing the host, meaning those changes don't need to be logged here.
