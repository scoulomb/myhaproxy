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



### Certificate generation prep

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

### Generate certificate

And finally we will generate our certificate

````
sudo /snap/bin/certbot certonly --standalone -d ha.coulombel.net -d nas-mgmt.coulombel.net -d music.coulombel.net -d musik.coulombel.net -d music-ha.coulombel.net -d webserver.coulombel.net -d player.coulombel.net
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
sudo cat /etc/letsencrypt/live/ha.coulombel.net/cert.pem /etc/letsencrypt/live/ha.coulombel.net/privkey.pem > mycert.pem
````

or execute `sudo /home/scoulomb/myhaproxy/mergecert.sh`

Where the order has an high importance. See more details at: https://hfiel.github.io/wiki/linux/haproxy_ssl_certificate_concatenation_for_pem.html


We can automate it to be compatible with renwal (cert bot time)

````
sudo crontab -e
# add
55 23 * * * /home/scoulomb/myhaproxy/mergecert.sh
````

we need to give permission 

````
chmod u+x  /home/scoulomb/myhaproxy/mergecert.sh
````

**Note mergecert should use the fullchain to work with curl**: https://community.letsencrypt.org/t/why-does-curl-not-trust-letsencrypt/183585/4

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
sudo docker run -v ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v /etc/letsencrypt/live/ha.coulombel.net:/certs -p 443:443 -p 70:70 haproxy
````


We can add `--restart=always` option to restart container at boot time and `-d` for detached mode


````
ssh scoulomb@raspberrypi5
cd myhaproxy; git pull
sudo docker kill $(sudo docker ps -a | grep haproxy | awk '{print $1}')
sudo docker rm $(sudo docker ps -a | grep haproxy | awk '{print $1}')
sudo docker run -v ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v /etc/letsencrypt/live/ha.coulombel.net:/certs -p 443:443 -p 70:70 --restart=always -d haproxy
````

and have a script [`restart.sh`](./restart.sh)



When using docker we have additional nat layer (port) - so 3 renat with ghome.

We can check config UI at `http://raspberrypi5:70/`


## Cert renwal failing?

If the case re-run command above from [generate certificate](#generate-certificate)

## Notes

- If TLS/NAT not setup we can test host header based routing via `curl --header 'Host: ha.coulombel.net' http://raspberrypi5:443/`
- Be careful to HA proxy config last line: https://stackoverflow.com/questions/68350378/unable-to-start-haproxy-2-4-missing-lf-on-last-line


## Advanced notes

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
  - As reminder check this representation:  https://github.com/scoulomb/private-ppt-repo/blob/main/README.md#public-tls-certificates <!-- reviewed with slides very clear OK STOP -->
  - Note there in diagram
    - Rigth
      - [1] `F5 server SSL`: `Client cert if mtls F5 <-> GW` linked to `Internal Server`:`SSLCACertificateFile` 
      - [2] `F5 server SSL`: `Certificate Authority  to trust (when private CA authority is used): ca-file` linked to `Internal server`:`TLS private cert`: `SSLCertificateFile`, `SSLCertificateKeyFile`
      - See https://github.com/scoulomb/misc-notes/blob/master/tls/in-learning-complement/learning-ssl-tld.md#acquire-a-webserver-certificate-using-openssl 
    - Left
      - [3] on `initial client` we can also have a `Client cert if mTLS client <-> F5` linked to `F5 client SSL`: `SSLCACertifcateFlle`
        - Not displayed in slide
      - [4] on `initial client`: we could have `Certificate Authority  to trust (when private CA authority is used): ca-file` linked to `F5 client SSL`:`TLS private cert`: `SSLCertificateFile`, `SSLCertificateKeyFile`
      - Again this pattern https://www.haproxy.com/documentation/haproxy-configuration-tutorials/ssl-tls/#tls-between-the-load-balancer-and-servers
        - **Usually a public cert is used here**
  
  - And here detail on client certificate: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/
    - Where HA proxy can verify client certificate as in F5 in [3]: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/#verify-client-certificates
    - Send certificate to server: `ssl crt` as in F5 in [1]: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/#send-a-client-certificate-to-servers (re-encrypt between ha proxy and backend)
  
  - For mTLS see also: https://github.com/scoulomb/misc-notes/blob/master/tls/tls-certificate.md#mutual-auth-mtls 
  
  - Usually server certificate on F5/HA proxy ((F5 client SSL) `SSLCertificateFile`) is signed by public CA (see in [self](#certificate-generation)) as mentionned in [4] 
  - And other signed by private CA as described here: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/#create-a-client-certificate.
  - Similar to what is explained here 
    - https://github.com/scoulomb/misc-notes/blob/master/tls/in-learning-complement/self-signed-certificate-with-custom-ca.md 
    - And here: https://github.com/scoulomb/misc-notes/blob/master/tls/in-learning-complement/learning-ssl-tld.md#linux-openssl-pki-environment [+] https://github.com/scoulomb/misc-notes/blob/master/tls/in-learning-complement/learning-ssl-tld.md#acquire-a-webserver-certificate-using-openss
    - Here we signed with private CA,a root CA cert is self-signed but we have also the option to self-sign a certificate
  
  - Take note we can decide (see [above](#we-have-seen-3-ways-to-access-internal-server-from-external))
    - A - Direct NAT - To not use a reverse proxy and manage certificate direcly on final server:https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md#add-certificates-alternative-use-a-reverse-proxy (what we can do for Jellyfin) [Initial option]
    - B - NAT to HA proxy - Use a reverse proxy and 
      - still manage certificate on final back-end, this is the passthrough mode as shown in slides here:  https://github.com/scoulomb/private-ppt-repo/blob/main/README.md#public-tls-certificates 
      - use reverse proxy as edge [Kept solution]
      - or re-encrypt 
    - Between A and B (edge), did not see major speed downgarde

- If backend is deployed via Kubernetes we still those 2 options: https://github.com/scoulomb/myk8s/blob/master/Services/service_deep_dive.md#cloud-edgeand-pop. Where when using ingress/openshift route itself can do re-encrypt beween ingress and pod (/private_script/blob/main/Links-mig-auto-cloud/certificate-doc/SSL-certificate-as-a-service-on-Openshift-4.md), passthrough, or edge:https://docs.openshift.com/container-platform/4.11/networking/routes/route-configuration.html
<!-- -private_script/blob/main/Links-mig-auto-cloud/listing-use-cases/listing-use-cases-appendix.md#si-inbound-links-in-pop-and-workload-in-azure-target-slide-8 --> 
<!-- stop here not detailled apigee cert OK independent could do it later -->
<!-- back end to back end call should be done via service inside cluster (ip:port) not via route (extra hop) or worse proxy: real life use-case seen - observed a random behavior depending on POD -->

### Authentification

- We could do authent with reverse proxy: https://www.navidrome.org/docs/usage/security/#reverse-proxy-authentication
See: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/ (tried and very simple)
- basic:https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/basic-authentication/ 

  ````
  ssh scoulomb@raspberrypi5
  cd myhaproxy; git pull
  sudo docker kill $(sudo docker ps -a | grep haproxy | awk '{print $1}')
  sudo docker rm $(sudo docker ps -a | grep haproxy | awk '{print $1}')
  sudo docker run -v ./haproxy/haproxy-basicauth.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v /etc/letsencrypt/live/ha.coulombel.net:/certs -p 443:443 -p 70:70  haproxy
  ````

  Then we can try in a browser or via curl

    ````
    $ curl -L --user "scoulomb:badpwd" https://music.coulombel.net | head -n 5
      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                    Dload  Upload   Total   Spent    Left  Speed
    100   112  100   112    0     0    280      0 --:--:-- --:--:-- --:--:--   280
    <html><body><h1>401 Unauthorized</h1>
    You need a valid user and password to access this content.
    </body></html>
    $ curl -L --user "scoulomb:mypassword" https://music.coulombel.net | head -n 5
      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                    Dload  Upload   Total   Spent    Left  Speed
    100    28  100    28    0     0    239      0 --:--:-- --:--:-- --:--:--   241
    100  2185    0  2185    0     0  17614      0 --:--:-- --:--:-- --:--:-- 17614
    <!doctype html><html lang="en"><head><meta charset="utf-8"/><meta name="description" content="Navidrome Music Server - v0.51.1 (6d253225)"/><link rel="apple-touch-icon" sizes="180x180" href="./apple-touch-icon.png"><link rel="icon" type="image/png" sizes="32x32" href="./favicon-32x32.png"><link rel="icon" type="image/png" sizes="192x192" href="./android-chrome-192x192.png"><link rel="icon" type="image/png" sizes="16x16" href="./favicon-16x16.png"><link rel="mask-icon" href="./safari-pinned-tab.svg" color="#5b5fd5"><meta name="msapplication-TileColor" content="#da532c"><meta name="theme-color" content="#ffffff"><meta name="viewport" content="width=device-width,initial-scale=1"/><link rel="manifest" href="./manifest.webmanifest"/><meta property="og:site_name" content="Navidrome"><meta property="og:url" content=""><meta property="og:title" content=""><meta property="og:image" content=""><meta property="og:image:width" content="300"><meta property="og:image:height" content="300"><title>Navidrome</title><script>window.__APP_CONFIG__ = "{\"baseURL\":\"\",\"defaultDownloadableShare\":false,\"defaultDownsamplingFormat\":\"opus\",\"defaultLanguage\":\"\",\"defaultTheme\":\"Dark\",\"defaultUIVolume\":100,\"devActivityPanel\":true,\"devShowArtistPage\":true,\"devSidebarPlaylists\":true,\"enableCoverAnimation\":true,\"enableDownloads\":true,\"enableExternalServices\":true,\"enableFavourites\":true,\"enableReplayGain\":true,\"enableSharing\":false,\"enableStarRating\":true,\"enableTranscodingConfig\":false,\"enableUserEditing\":true,\"firstTime\":false,\"gaTrackingId\":\"\",\"lastFMEnabled\":false,\"listenBrainzEnabled\":true,\"loginBackgroundURL\":\"/backgrounds\",\"losslessFormats\":\"ALAC,APE,DSF,FLAC,SHN,TAK,WAV,WV,WVP\",\"maxSidebarPlaylists\":100,\"variousArtistsId\":\"03b645ef2100dfc42fa9785ea3102295\",\"version\":\"0.51.1 (6d253225)\",\"welcomeMessage\":\"\"}"</script><script>window.__SHARE_INFO__ =  null </script><script defer="defer" src="./static/js/main.0b7df61b.js"></script><link href="./static/css/main.90bfad59.css" rel="stylesheet"></head><body><noscript>You need to enable JavaScript to run this app.</noscript><div id="root"></div></body></html>scoulomb@scoulomb-Precision-3540:~$ 

    ````


- client cert (see [bullet above](#ha-proxy-and-f5-re-encryption-comparison)): https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/client-certificate-authentication/ (not tried)  <!-- stop here -->

Note client certificate does not encrypt the data, it enables to indentify the client: https://sectigostore.com/page/client-certificate-vs-server-certificate/

We are in client authentification/SSL-TLS (client) case/Identify CA (as cert signed by CA) depicted in https://github.com/scoulomb/misc-notes/blob/master/tls/tls-certificate.md#note-cert-can-be-used-for: Cert signed by CA, identify client but not used to encryp data.

Note Server certificate signed by CA, idnetify server and used to encrypt.


- oAuth 2 : https://www.haproxy.com/documentation/haproxy-configuration-tutorials/authentication/oauth-authorization/ (https://github.com/scoulomb/misc-notes/tree/master/oauth). Here we use client credentials oauth flow with an id token. <!-- stop here -->
So we are in client credential grant type https://github.com/scoulomb/misc-notes/blob/master/oauth/3-oauth2.0-client-credentials.puml, extended with id_token.
Here we had extended authorization code grant type with id token: https://github.com/scoulomb/misc-notes/blob/master/oauth/99-oauth2.0andOpenID.puml#L3

  - Get a JWT with Auth0 

  ````
  $ curl --request POST \
    --url https://dev-vntgo8751m30psu0.us.auth0.com/oauth/token \
    --header 'content-type: application/json' \
    --data '{"client_id":"AGBI276O0PetNIrQr4O6nCJzWmK4jzBo","client_secret":"ZCm_N1MsgDEwvMPm5VQBROroFd_CVH2-e6YN-IUlh0fAYAa88gTG2Eis2urc2trO","audience":"music.coulombel.net","grant_type":"client_credentials"}'
  {"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkJyQWNKTGhXZFdNS2FTSEc3QjFHSyJ9.eyJpc3MiOiJodHRwczovL2Rldi12bnRnbzg3NTFtMzBwc3UwLnVzLmF1dGgwLmNvbS8iLCJzdWIiOiJBR0JJMjc2TzBQZXROSXJRcjRPNm5DSnpXbUs0anpCb0BjbGllbnRzIiwiYXVkIjoibXVzaWMuY291bG9tYmVsLm5ldCIsImlhdCI6MTcxNTYxNjg0NywiZXhwIjoxNzE1NzAzMjQ3LCJndHkiOiJjbGllbnQtY3JlZGVudGlhbHMiLCJhenAiOiJBR0JJMjc2TzBQZXROSXJRcjRPNm5DSnpXbUs0anpCbyJ9.gGkBpXgpFKt9AO6Pi8MHomDhAWdzeF8nnTSQ0QIVJPSkV-jYgMJVOclaVFM-q1WjT7rKcMmhawYcPibXDVOHlmhSJ21uZAzQMS0jKKBnekxQj9FHeKv2aVj4vwzxqyBbIquhpUKAQz7ZAVBzhL8r3IfTUCvdH1E1YfRjHSFfSZMp_ac_x9TBO0VsTgVW7BbQSNw30gdoh3-bIBkRUWjiQsQdCTF_oFXjU317nKZdBX-ckBpi2PAyQmF7L0-fN_pBJSy3_C_oFldCh1rUvj_hASuuQGCIQiiLukXMqPQPKtjAurEorOvVlXxd2Zk4lWgHCYw-TPYu8vvm02v3Mar61g","expires_in":86400,"token_type":"Bearer"}
  ````

  - Configure the load balancer with RS256 
    - Certificate 

      ````
      openssl x509 -pubkey -noout -in  ./haproxy/client-credentials-certificate/dev-vntgo8751m30psu0.pem >  ./haproxy/client-credentials-certificate/pubkey.pem
      ````
    - Update config file (we can use JWT viewer to set correct parameters)
    - Launch HA proxy

      ````
      cd myhaproxy; git pull
      sudo docker kill $(sudo docker ps -a | grep haproxy | awk '{print $1}')
      sudo docker rm $(sudo docker ps -a | grep haproxy | awk '{print $1}')
      sudo docker run -v ./haproxy/client-credentials-certificate:/client-credentials-certificate:ro -v ./haproxy/haproxy-oauth-client-credentials.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v /etc/letsencrypt/live/ha.coulombel.net:/certs -p 443:443 -p 70:70  haproxy
      ````
    - Try

      ````
      $ curl -L --request GET  --url https://music.coulombel.net/   --header 'authorization: Bearer Invalid'
      Unsupported JWT signing algorithm
      
      $ curl -L --request GET  --url https://music.coulombel.net/   --header 'authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkJyQWNKTGhXZFdNS2FTSEc3QjFHSyJ9.eyJpc3MiOiJodHRwczovL2Rldi12bnRnbzg3NTFtMzBwc3UwLnVzLmF1dGgwLmNvbS8iLCJzdWIiOiJBR0JJMjc2TzBQZXROSXJRcjRPNm5DSnpXbUs0anpCb0BjbGllbnRzIiwiYXVkIjoibXVzaWMuY291bG9tYmVsLm5ldCIsImlhdCI6MTcxNTYxNjg0NywiZXhwIjoxNzE1NzAzMjQ3LCJndHkiOiJjbGllbnQtY3JlZGVudGlhbHMiLCJhenAiOiJBR0JJMjc2TzBQZXROSXJRcjRPNm5DSnpXbUs0anpCbyJ9.gGkBpXgpFKt9AO6Pi8MHomDhAWdzeF8nnTSQ0QIVJPSkV-jYgMJVOclaVFM-q1WjT7rKcMmhawYcPibXDVOHlmhSJ21uZAzQMS0jKKBnekxQj9FHeKv2aVj4vwzxqyBbIquhpUKAQz7ZAVBzhL8r3IfTUCvdH1E1YfRjHSFfSZMp_ac_x9TBO0VsTgVW7BbQSNw30gdoh3-bIBkRUWjiQsQdCTF_oFXjU317nKZdBX-ckBpi2PAyQmF7L0-fN_pBJSy3_C_oFldCh1rUvj_hASuuQGCIQiiLukXMqPQPKtjAurEorOvVlXxd2Zk4lWgHCYw-TPYu8vvm02v3Mar61g'
      <!doctype html><html lang="en"><head><meta charset="utf-8"/><meta name="description" content="Navidrome Music Server - v0.51.1 (6d253225)"/><link rel="apple-touch-icon" sizes="180x180" href="./apple-touch-icon.png"><link rel="icon" type="image/png" sizes="32x32" href="./favicon-32x32.png"><link rel="icon" type="image/png" sizes="192x192" href="./android-chrome-192x192.png"><link rel="icon" type="image/png" sizes="16x16" href="./favicon-16x16.png"><link rel="mask-icon" href="./safari-pinned-tab.svg" color="#5b5fd5"><meta name="msapplication-TileColor" content="#da532c"><meta name="theme-color" content="#ffffff"><meta name="viewport" content="width=device-width,initial-scale=1"/><link rel="manifest" href="./manifest.webmanifest"/><meta property="og:site_name" content="Navidrome"><meta property="og:url" content=""><meta property="og:title" content=""><meta property="og:image" content=""><meta property="og:image:width" content="300"><meta property="og:image:height" content="300"><title>Navidrome</title><script>window.__APP_CONFIG__ = "{\"baseURL\":\"\",\"defaultDownloadableShare\":false,\"defaultDownsamplingFormat\":\"opus\",\"defaultLanguage\":\"\",\"defaultTheme\":\"Dark\",\"defaultUIVolume\":100,\"devActivityPanel\":true,\"devShowArtistPage\":true,\"devSidebarPlaylists\":true,\"enableCoverAnimation\":true,\"enableDownloads\":true,\"enableExternalServices\":true,\"enableFavourites\":true,\"enableReplayGain\":true,\"enableSharing\":false,\"enableStarRating\":true,\"enableTranscodingConfig\":false,\"enableUserEditing\":true,\"firstTime\":false,\"gaTrackingId\":\"\",\"lastFMEnabled\":false,\"listenBrainzEnabled\":true,\"loginBackgroundURL\":\"/backgrounds\",\"losslessFormats\":\"ALAC,APE,DSF,FLAC,SHN,TAK,WAV,WV,WVP\",\"maxSidebarPlaylists\":100,\"variousArtistsId\":\"03b645ef2100dfc42fa9785ea3102295\",\"version\":\"0.51.1 (6d253225)\",\"welcomeMessage\":\"\"}"</script><script>window.__SHARE_INFO__ =  null </script><script defer="defer" src="./static/js/main.0b7df61b.js"></script><link href="./static/css/main.90bfad59.css" rel="stylesheet"></head><body><noscript>You need to enable JavaScript to run this app.</noscript><div id="root"></div></body></html>s
      
      ````

- Note this authentification add layer which may not always work with some client (Navidrome/Subsonic client (Amperfy)): https://github.com/scoulomb/home-assistant/blob/main/appendices/DNS.md#add-certificates-alternative-use-a-reverse-proxy 

- Here cert is used to sign token (via private key and signature verified using public key)

<!--
- This is linked to /Links-mig-auto-cloud/listing-use-cases/listing-use-cases-appendix.md#cloudification-is-a-pre-req-to-migration
-->

<!-- basic auth and jwt bearer token validated and tested with commands supplied OK -->


**Will not**
- Will not explore something not client credentials grant type with Auth0 (authorization code expects to have a UI on top)
- Will not try client cert mtls
- And proxy server (see wiki) in browser different (Amperfy not possible with credentials)


- Comment on token
  - Note auth0, access token is also an id_token, not a separate field as in here: https://github.com/scoulomb/misc-notes/blob/master/oauth/99-oauth2.0andOpenID.puml#L43
  - ID Token validation is done on application side using certificate (signature). Some IDP/OIDC have endpoint to validate id token: https://community.auth0.com/t/validating-an-access-token/71540, https://stackoverflow.com/questions/64758965/okta-introspect-endpoint-always-returns-false
  - ID token contains user info and permission 
  - Some OIDC provider also enable to exchange access token with user info / permission: https://github.com/scoulomb/misc-notes/blob/master/oauth/99-oauth2.0andOpenID.puml#L43, see here with Google: https://www.oauth.com/oauth2-servers/signing-in-with-google/verifying-the-user-info/ (does not seem to be case for auth0)
  - Auth0 is using Google OIDC when login with google account (inception). They get userinfo
  

<!--@Real life 
Use Microsoft oauth server: "Authentication+Mechanism Network+automation" to get token with authorization code and client credentials grant type
== Question: toke validation (certificate?) how done

Use internal auth server to get token
1. internal openid a la client credentials grant type (with id token or exchange access token, later is implemented currently) 
2. central _l _p internal "internal" API used by UI, and  exception to be used from orchestrator 
3. aauth auth header (but not allowed when no service integration)
4. or via a workflow exception in 2

See mel: Robotic access to LNK

== Question: can we use token got in 2, same way if 1, so that only client inpact

Optional to complement here ==question
-->

<!-- pkce not rel to cert -->

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


Here: https://github.com/scoulomb/birthday-counter, server valudation made directly by hosting (as DNS pointing to their public IP) <!-- stop -->

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


Note: those file can edited directly from PI 5.

## OPTIONAL Improvements

- Cert renewal. See `## Cert renwal failing?` section
- Understand better `set-uri` and link with, as it is equivalent: https://github.com/open-denon-heos/remote-control/blob/main/apache-setup/heos.conf
