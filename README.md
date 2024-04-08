# myhaproxy

HA proxy setup


## Use docker compose

Compose file can be inspired from: https://github.com/yeasy/docker-compose-files/blob/master/haproxy_web/haproxy/haproxy.cfg

Note the usage of service link in HA proxy and config,

How to setup docker and compose on raspberry PI 5: Follow this tuto: https://www.kevsrobots.com/blog/build-a-home-server

````
sudo apt update && sudo apt upgrade 
curl -sSL https://get.docker.com | sh
docker --version

sudo apt install libffi-dev python3-dev python3-pip
sudo pip3 install docker-compose --break-system-packages # we added --break-system-packages + specify version as there was a bug latest one on cython with yaml package
sudo pip3 install docker-compose==1.23.0 --break-system-packages
docker-compose --version # may have to restart a new shell
````

Then 

````
git clone https://github.com/scoulomb/myhaproxy.git
git pull
docker-compose up
````

But here is an issue with compose when doing `up`: AributeError: module 'collections' has no attribute 'Hashable'


sudo docker run haproxy:2.7 -v ./haproxy:/haproxy-override -v ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -p "80:80" -p "443:443" -p "70:70" # haproxy admin console, login with user:pass