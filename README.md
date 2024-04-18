# myhaproxy

HA proxy setup


See https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md

## Introduction 

Can we do better that what is shown in [`Add certificates`](https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md#add-certificates) section?
In [objective 2](https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md#objective-2) we need to backport the certificate to home assistant (and each new service we want to offer)
And same operation woud be required with [objective 1](https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md#objective-1-ha-in-https) to import certificate to QNAP.

Also we need to NAT each port (443 - QMAP mgmt UI, 8123 - for HA) and it implies usage of non standard port.

Ideally we would want to target 
- `https://ha.coulombel.net`
- `https://nas-mgmt.coulombel.net`

And we can add other services: music services, webserver

- `https://music.coulombel.net`
- `https://musik.coulombel.net`
- `https://webserver.coulombel.net`

With `443` default port.

And open only 443 port, and redirect 80 to 443. 

This ideal world is possible with a reverse proxy.

## Tenative to use QNAP integrated reverse proxy

I followed this [guide](./DNS-reverse-proxy-doc/revproxyqnap.pdf)

https://www.qnap.com/en/how-to/tutorial/article/how-to-use-reverse-proxy-to-improve-secure-remote-connections

It is working well in particular to route to a docker container based on DNS names (host header based routing).

However certificate made with [objective 2](#objective-2) has to accept addiitional ALT names for the connection to be secured.
We faced several issues
- https://forum.qnap.com/viewtopic.php?t=154082: 
  - For coulombel.net (error visible only if not requesting scoulomb.myqnapcloud.com)
  - > "a domain validation challenge was not received from ACME server. Ensure that your router and QNAP device both accept inbound traffic on ports 80 and 443 which is a requirement from let's encrypt."
  - on top NAT rules are OK, webserver in port 80 disabled, reverse proxy disabled, nas managememt (system>system administation on 8443), seems issue on QNAP side
- https://forum.qnap.com/viewtopic.php?t=173862
  - And on top even QNAP domain faced issue

In the end those certificates management in QNAP is just a mess. 


We can do proposed solution in section below:

## Own cert management and reverse proxy based HA proxy, moved out of QNAP (and dynDNS if it would be required)


As bonus point it allow to
- Not not have the NAS exposed directly to Internet.
- And external service access behavior to not impact internal behavior.


## Preparation 

I do not need the `scoulomb.qnapcloud.com` so I will not request it, but nothing prevents from adding it in ALT names.
The [qnap smart URL](https://github.com/scoulomb/home-assistant/blob/main/appendices/file-sharing/qnap-smart-url.md) impacted but should continue to work.

I assume following setup and desired mapping


- `https://ha.coulombel.net` --> `http://scoulombel-nas:8123` (HA svc in container station) where we removed TLS certificate, remember HA does not support TLS and non TLS at same time)

For this via filestation update `home-assistant-docker/configuration.yaml` and rm lines + restart container to remove TLS setup from assistant made in https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md since we use reverse proxy.

````
http:
  ssl_certificate: ./tls/QNAPCert/SSLcertificate.crt
  ssl_key: ./tls/QNAPCert/SSLprivatekey.key

````


- `https://nas-mgmt.coulombel.net`-> `http://scoulombel-nas:8080` (control panel > general settings > system administration)(we have also the mgmt UI at https://scoulombel-nas:443, also given ha proxy is not on nas I can re-use https/443 here, unlike this doc: https://www.qnap.com/en/how-to/tutorial/article/how-to-use-reverse-proxy-to-improve-secure-remote-connections)
- `https://music.coulombel.net` -> `http://scoulombel-nas:4533` navidrome svc in container station) *
- `https://musik.coulombel.net` -> `http://scoulombel-nas:8096`(jellyfin svc in contanier station) *
<!--- `https://music-ha.coulombel.net` -> `http://scoulombel-nas:custom`(music assistant svc in contanier station with custom port as sharing hellyfin one: https://music-assistant.io/installation/) [excluded as no sense outside in the end] -->
- `https://webserver.coulombel.net` -> `http://scoulombel-nas:80` (control panel > Webserver, we also ahve https://scoulombel-nas:8081) 

* Additional services on top of the one depicted in https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md

And the beauty is that we only need as NAT rule for HTTP traffic

- For HA proxy
  - `http://192.168.1.1/network/nat` => `ha-proxy 	TCP 	Port 	443 	192.168.1.58 	22443`
  - `gHome` > `Port mgmt` > `22443 -> 443`  of HA proxty server 

- For cert renwal and validation

  - `http://192.168.1.1/network/nat` => `cert-valid 	TCP 	Port 	80 	192.168.1.58 	22080`
  - `gHome` > `Port mgmt` > `22080 -> 80`  of HA proxy server 

We will use Raspberry PI 5 as HA proxy server (to setup PI5, build os with PI imager with advanced option for SSH, setup Wifi via GUI, need to set wlan country, we need to have vlan country compatbile with langauge and localisation(FR) otherwise will not work, see https://github.com/scoulomb/docking-station#raspi for wiring using free HDMI and usb switch).

I also ensure QNAP to use in
- Control panel > security > SSL cert and private key: default certificate (in myQNAPCloudApp therefore nothing is configured)
- Control panel > network and file service > network access > reverse proxy is disabled


We setup in google damin the 5 A records to my fix IP (here not dynDNS)


## HA proxy configuration 



### Certificate generation

First we need to gnerate certificate on the Raspberry


We will install certbot following instructions here: https://snapcraft.io/install/certbot/raspbian

````
ssh scoulomb@raspberrypi5

sudo apt update
sudo apt install snapd

sudo reboot

sudo snap install core

sudo snap install certbot --classic
````

Then if certbot is not found 

````
scoulomb@raspberrypi5:~ $ which certbot
/snap/bin/certbot
````


And finally we will generate our certificate

````
sudo /snap/bin/certbot certonly --standalone -d ha.coulombel.net -d nas-mgmt.coulombel.net -d music.coulombel.net -d musik.coulombel.net -d music-ha.coulombel.net -d webserver.coulombel.net 
````


output is 

````
Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/ha.coulombel.net/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/ha.coulombel.net/privkey.pem
This certificate expires on 2024-07-07.
````

Given we are using webserver DCV we need NAT rules to go to PI 5 port 80.


However we are not there yet, for the certificate to be usable by ha proxy we need to merge the cert and private key in a single file

````
cat /etc/letsencrypt/live/ha.coulombel.net/cert.pem /etc/letsencrypt/live/ha.coulombel.net/privkey.pem > mycert.pem
````


Where the order has an high importance. See more details at: https://hfiel.github.io/wiki/linux/haproxy_ssl_certificate_concatenation_for_pem.html


We can automate it to be compatible with renwal (cert bot time)

````
sudo crontab -e
# add
55 23 * * * /home/scoulomb/myhaproxy/mergecert.sh
````

## Create the config 

See [HA proxy config](./haproxy/haproxy.cfg)

Links
- Basic of HA proxy: https://www.haproxy.com/blog/haproxy-configuration-basics-load-balance-your-servers
- Direct mapping instead of using ACLs: https://www.haproxy.com/blog/how-to-map-domain-names-to-backend-server-pools-with-haproxy
- See here TLS setup: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/ssl-tls/
<!-- note we can have TLS between front and pools as cloudif -->
- 

## Use docker compose for deployment

We will favor docker over direct setup on os, to jsut install docker on raspberry



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
sudo docker ps | grep haproxy 
sudo docker kill 34198b958429 


# Port 70 for haproxy admin console, login with user:pass
cd myhaproxy
sudo docker run -v ./haproxy:/haproxy-override -v ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v /etc/letsencrypt/live/ha.coulombel.net:/certs -p 443:443 -p 70:70 haproxy
````


We cab add `--restart=always` option to restart container at boot time and `-d` for detached mode


````
ssh scoulomb@raspberrypi5
cd myhaproxy; git pull
sudo docker kill $(sudo docker ps -a | grep haproxy | awk '{print $1}')
sudo docker rm $(sudo docker ps -a | grep haproxy | awk '{print $1}')
sudo docker run -v ./haproxy:/haproxy-override -v ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v /etc/letsencrypt/live/ha.coulombel.net:/certs -p 443:443 -p 70:70 --restart=always -d haproxy
````

When using docker we have additional nat layer (port) - so 3 renat with ghome.

We can check config UI at `http://raspberrypi5:70/`


## Notes

- If TLS/NAT not setup we can test host header based routing via `curl --header 'Host: ha.coulombel.net' http://raspberrypi5:443/`
- Be careful to HA proxy config last line: https://stackoverflow.com/questions/68350378/unable-to-start-haproxy-2-4-missing-lf-on-last-line


## Advanced notes [only here to review - remain is CCL]

### Access to music server 

This is described at https://github.com/scoulomb/home-assistant/blob/main/appendices/sound-video/setup-your-own-media-server-and-music-player.md

### We have seen 3 ways to access internal server from external 

- Direct NAT: https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md
- NAT to HA proxy: [self](README.md): we NAT the HA proxy port (double nat with ghome) and port forwarding to container
    - I did not redirect HTTP to HTTPS in my HA proxy for certbot validation and thusnot forward port 80 in container
- VPN : https://github.com/scoulomb/home-assistant/blob/main/appendices/VPN.md, where we we (double if ghome) NAT the VPN port
    - Tailscale manage NAT traversal without NAT rules: https://tailscale.com/blog/how-nat-traversal-works

This is complaint with https://www.wundertech.net/how-to-access-jellyfin-remotely/

### Run workload on NAS or Raspi?

Also I will keep hosting server on QNAP, for instance jellyfish recomend atom cpu for transcoding: https://jellyfin.org/docs/general/administration/hardware-acceleration/

### k8s and HA proxy

Also K8s uses HA proxy to route to service, see detail at: https://github.com/scoulomb/myk8s/blob/master/Services/service_deep_dive.md#when-using-ingress

Good summary of end to end setup: https://github.com/scoulomb/myk8s/blob/master/Services/service_deep_dive.md#cloud-edgeand-pop
<!-- was ccl OK and recheck OK -->
<!-- And link to private_script/blob/main/Links-mig-auto-cloud/listing-use-cases/listing-use-cases-appendix.md#pre-req and  + proxy office end of doc OK STOP -->
 Here we use HA proxy which is used by Openshift route. We also have Traefik which is mentionned in  https://www.navidrome.org/docs/usage/security/#reverse-proxy-authentication, and we saw it can be used in k8s, see https://github.com/scoulomb/myk8s/blob/master/Services/service_deep_dive.md#see-traefik-gui


### HA proxy and F5 re-encryption comparison


- HA proxy is a kind of load balancer we can threfore also re-encrypt traffic.
  - As reminder check this representation:  https://github.com/scoulomb/private-ppt-repo/blob/main/README.md#public-tls-certificates 
  - Note there in diagram
    - `Client cert if mtls F5 <-> GW` linked to `SSLCACertificateFile` 
    - `Certificate Authority  to trust (when private CA authority): ca-file` linked to `TLS private cert` https://github.com/scoulomb/misc-notes/blob/master/tls/in-learning-complement/learning-ssl-tld.md#acquire-a-webserver-certificate-using-openssl 
    - on `F5 client SSL` we could also have `SSLCACert` file as k8s server on the rigth, and with client cert mtls on initial client (at left)
  - We have the equivlalent here: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/ssl-tls/#tls-between-the-load-balancer-and-servers
  - And here detail on client certificate: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/
    - Where HA proxy can verify client certificate with `ca-file` (equivalent to `SSLCACert`)
    - Send certificate to server: `ssl crt` (equivalent to `Client cert if mtls F5 <-> GW`) )
  - For mTLS see also: https://github.com/scoulomb/misc-notes/blob/master/tls/tls-certificate.md#mutual-auth-mtls (certificate and server certificate are signed, usuallty server certificate on F5/HA proxy is signed by public CA (see in [self](#certificate-generation) and other signed by private CA (as described here: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/
  #create-a-client-certificate. Server certificate signed by private CA are acquired the same way as described in 
    - https://github.com/scoulomb/misc-notes/blob/master/tls/in-learning-complement/self-signed-certificate-with-custom-ca.md 
    - And here: https://github.com/scoulomb/misc-notes/blob/master/tls/in-learning-complement/learning-ssl-tld.md#linux-openssl-pki-environment [+] https://github.com/scoulomb/misc-notes/blob/master/tls/in-learning-complement/learning-ssl-tld.md#acquire-a-webserver-certificate-using-openss
    - Here we signed with private CA,a root CA cert is self-signed but we have also the option to self-sign a certificate

- We could do authent with reverse proxy: https://www.navidrome.org/docs/usage/security/#reverse-proxy-authentication
See: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/
  - basic
  - client cert (see bullet above)
  - oAuth 2 (https://github.com/scoulomb/misc-notes/tree/master/oauth) <!-- stop here -->

<!--
- This is linked to /Links-mig-auto-cloud/listing-use-cases/listing-use-cases-appendix.md#cloudification-is-a-pre-req-to-migration
-->

### HA proxy and F5 source IP preservation

HA proxy can also preserve source IP: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/client-ip-preservation/enable-proxy-protocol/ 

<!--
- This is linked to /Links-mig-auto-cloud/listing-use-cases/listing-use-cases-appendix.md#cloudification-is-a-pre-req-to-migration
-->

### HA proxy and F5 virtual server and Azure LB

- Azure load balancer can support multiple IP: https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-multivip-overview.
More exactly 600 hundreds: https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#load-balancer
When using k8s `serviceType: LoadBalancer`, driver can create a new loadbalancer or app port to load balancer. <!-- See link private_script/blob/main/Links-mig-auto-cloud/listing-use-cases/listing-use-cases-appendix.md#si-inbound-links-in-pop-and-workload-in-azure-target-slide-8, here we add port to LB which is per farm/macxrophase -->

- F5 has same concepts with virtual server

- F5 load  balancer are not doing routing. F5 virtual server listens on deicated virtual IP:virtual Port and BGP do the routing to F5.
Though we can have some interaction between router and F5: https://www.rwolfe.io/advertising-healthy-f5-ltm-vips-using-bgp/
<!-- slide design v2 automatic route on path but for fw from /private_script/blob/main/Links-mig-auto-cloud/listing-use-cases/listing-use-cases.md#links-migration-listing-all-use-cases ==> sharepoint -->

- What about my HA proxy?
  - First HA proxy has the concept of frontend/backend and listen: https://stackoverflow.com/questions/39209917/difference-between-frontend-backend-and-listen-in-haproxy -> http://cbonte.github.io/haproxy-dconv/1.6/configuration.html#4
    - > A "frontend" section describes a set of listening sockets accepting client connections.
    - > A "backend" section describes a set of servers to which the proxy will connect to forward incoming connections.
    - > A "listen" section defines a complete proxy with its frontend and backend parts combined in one section. It is generally useful for TCP-only traffic.
    - From SO: > A listen has an implicit default_backend of itself
    - We can see it in action in our [proxy config](./haproxy/haproxy.cfg) for both (listen to HA proxy UI)
  - Let's look at frontend documentation: https://www.haproxy.com/docuemntation/haproxy-configuration-tutorials/core-concepts/frontends/
    - Here https://www.haproxy.com/documentation/haproxy-configuration-tutorials/core-concepts/frontends/#use-multiple-frontends-for-different-traffic-types
      - Here we use 2 front end for 2 differents `IPs:Port` and traffic type
      ````
      frontend foo.com
        mode http
        bind 192.168.1.5:80
        default_backend foo_servers
      frontend db.foo.com
        mode tcp
        bind 192.168.1.15:3306
        default_backend db_servers
      ````
      - This the most equivalent to F5 virtual server
      - HA proxy allows also 1 front end to listen on mutiple IP and port: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/core-concepts/frontends/#listen-on-multiple-ip-addresses-and-ports
        - When we do `:80`, we listen on all IP adresses targetting the server at this port (equivalent to `0.0.0.0`, and IPv6: https://stackoverflow.com/questions/27480094/ipv6-is-equivalent-to-0-0-0-0-when-listening-for-connections), we can also do port range `bind 192.168.1.5:8080-8090`, and listen on all IPv4+6 `bind [::]:80 v4v6`. 
      - And our front end [proxy config](./haproxy/haproxy.cfg), we have 2 ports with all interfaces but I have only my provider IP, which is NAT distributed to myhaproxy
      - See also: https://serverfault.com/questions/310493/haproxy-with-multiple-ip-in-one-server

### DCV validation methods

We have used Webserver validation method here, bit other ways are possbile (DNS, email)
See
- https://letsencrypt.org/docs/challenge-types/
- https://support.comodoca.com/articles/Knowledge/Domain-Control-Validation-DCV-Methods
- https://docs.digicert.com/en/certcentral/manage-certificates/dv-certificate-enrollment/domain-control-validation--dcv--methods.html


### SNI

We used a SAN certficate and HA proxy can also mamange a SNI folder

### HA proxy routing

Can be based on 
- Host header: https://www.haproxy.com/blog/how-to-map-domain-names-to-backend-server-pools-with-haproxy [ACL, direct map, map based routing]
- HTTP path: https://www.haproxy.com/blog/path-based-routing-with-haproxy (`path`, `path_beg` or `map file` (-> linked to https://www.haproxy.com/blog/introduction-to-haproxy-maps))

Advanced:: we can use map based routing for host header and http path based routing,
But can it be more customizable. 
- For path based: it can map beginning, end, subrsring and regex of a path 
- For host based: it can map a domain.

We can also map a source IP.
See https://www.haproxy.com/blog/introduction-to-haproxy-maps

Do not confuse with SNI certificate selection and host header based routing, SNI is pure TLS: https://fr.wikipedia.org/wiki/Server_Name_Indication 
<!-- see page high level design elm -->

See /private_script/blob/main/Links-mig-auto-cloud/listing-use-cases/listing-use-cases-appendix.md#ingress-usage-or-not

### Raspi 

We can use desktop UI to go faster

### Why We can use HA proxy URL


It is because of NAT loopback at home: https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md#nat-loopback

---
