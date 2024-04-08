# myhaproxy

HA proxy setup

## See certificate creation 

https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md#ha-proxy-configuration 

## Create the config 

See [HA proxy config](./haproxy/haproxy.cfg)

Links
- Basic of HA proxy: https://www.haproxy.com/blog/haproxy-configuration-basics-load-balance-your-servers
- Direct mapping instead of using ACLs: https://www.haproxy.com/blog/how-to-map-domain-names-to-backend-server-pools-with-haproxy
- See here TLS setup: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/ssl-tls/
<!-- note we can have TLS between front and pools as cloudif -->
- 

## Use docker compose for deployment



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
ssh scoulomb@raspberrypi5
git clone https://github.com/scoulomb/myhaproxy.git
git pull
docker-compose up
````

But here is an issue with compose when doing `up`: AributeError: module 'collections' has no attribute 'Hashable'

As an alternative we will run equvalent config via docker directly:

````
ssh scoulomb@raspberrypi5
git clone https://github.com/scoulomb/myhaproxy.git
git pull

# if other instance running
sudo docker ps grep haproxy 
sudo docker kill 34198b958429 

# Port 70 for haproxy admin console, login with user:pass
cd myhaproxy
sudo docker run -v ./haproxy:/haproxy-override -v ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v /etc/letsencrypt/live/ha.coulombel.net:/certs -p 443:443 -p 70:70 haproxy
````

When using docker we have additional nat layer (port)

We can check config UI at `http://raspberrypi5:70/`


## Notes

- If TLS not setup we can test host header based routing via `curl --header 'Host: ha.coulombel.net' http://raspberrypi5:443/`
- Becareful to HA proxy config last line: https://stackoverflow.com/questions/68350378/unable-to-start-haproxy-2-4-missing-lf-on-last-line