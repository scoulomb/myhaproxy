git pull
sudo docker kill $(sudo docker ps -a | grep haproxy | awk '{print $1}')
sudo docker rm $(sudo docker ps -a | grep haproxy | awk '{print $1}')
sudo docker run -v ./haproxy:/haproxy-override -v ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v /etc/letsencrypt/live/ha.coulombel.net:/certs -p 443:443 -p 70:70 --restart=always -d haproxy

