#!/bin/bash

TOPO_FILE="topology.yml"

echo "Starting lab"

# Containerlab
echo -n "Containerlab deployment"
sudo containerlab deploy -t "$TOPO_FILE"

# Router (FRR)
echo -n "Starting FRR router"
kitty --title="router" bash -c "docker exec -it clab-pg-lab-router bash -c 'kill \$(cat /var/run/frr/watchfrr.pid 2>/dev/null) 2>/dev/null; /usr/lib/frr/frrinit.sh start; exec bash'" &

echo -n "Waiting for router OSPF"
sleep 3
echo "Ok"

kitty --title="etcd1" bash -c "docker exec -it clab-pg-lab-etcd1 bash -c 'etcd --name etcd1 --initial-cluster etcd1=http://clab-pg-lab-etcd1:2380,etcd2=http://clab-pg-lab-etcd2:2380,etcd3=http://clab-pg-lab-etcd3:2380 --initial-cluster-state new --initial-advertise-peer-urls http://clab-pg-lab-etcd1:2380 --listen-peer-urls http://[::]:2380 --listen-client-urls http://[::]:2379 --advertise-client-urls http://clab-pg-lab-etcd1:2379 --data-dir /tmp/etcd-data & exec bash'" &
sleep 5

# etcd2
kitty --title="etcd2" bash -c "docker exec -it clab-pg-lab-etcd2 bash -c 'etcd --name etcd2 --initial-cluster etcd1=http://clab-pg-lab-etcd1:2380,etcd2=http://clab-pg-lab-etcd2:2380,etcd3=http://clab-pg-lab-etcd3:2380 --initial-cluster-state new --initial-advertise-peer-urls http://clab-pg-lab-etcd2:2380 --listen-peer-urls http://[::]:2380 --listen-client-urls http://[::]:2379 --advertise-client-urls http://clab-pg-lab-etcd2:2379 --data-dir /tmp/etcd-data & exec bash'" &
sleep 5

# etcd3
kitty --title="etcd3" bash -c "docker exec -it clab-pg-lab-etcd3 bash -c 'etcd --name etcd3 --initial-cluster etcd1=http://clab-pg-lab-etcd1:2380,etcd2=http://clab-pg-lab-etcd2:2380,etcd3=http://clab-pg-lab-etcd3:2380 --initial-cluster-state new --initial-advertise-peer-urls http://clab-pg-lab-etcd3:2380 --listen-peer-urls http://[::]:2380 --listen-client-urls http://[::]:2379 --advertise-client-urls http://clab-pg-lab-etcd3:2379 --data-dir /tmp/etcd-data & exec bash'" &
sleep 5

# node 1
echo -n "Starting Patroni node 1"
kitty --title="node1" bash -c "docker exec -it clab-pg-lab-node1 patroni /etc/patroni.yml" &
echo -n "Waiting for node1 Patroni API"
until docker exec clab-pg-lab-node1 timeout 1 bash -c 'echo > /dev/tcp/127.0.0.1/8008' 2>/dev/null; do
  echo -n "."
  sleep 1
done
echo "Ok"

# node 2
echo -n "Starting Patroni node2"
kitty --title="node2" bash -c "docker exec -it clab-pg-lab-node2 patroni /etc/patroni.yml" &
echo -n "Waiting for node2 Patroni API"
until docker exec clab-pg-lab-node2 timeout 1 bash -c 'echo > /dev/tcp/127.0.0.1/8008' 2>/dev/null; do
  echo -n "."
  sleep 1
done
echo "Ok"

docker exec -u root clab-pg-lab-haproxy1 bash -c 'ip addr add 172.20.22.21/24 dev eth0' 2>/dev/null
docker exec -u root clab-pg-lab-haproxy2 bash -c 'ip addr add 172.20.22.22/24 dev eth0' 2>/dev/null

docker exec -d clab-pg-lab-node1 node_exporter --web.listen-address=:9100 2>/dev/null
docker exec -d clab-pg-lab-node2 node_exporter --web.listen-address=:9100 2>/dev/null

# haproxy1
echo -n "Starting HAProxy1"
kitty --title="haproxy1" bash -c "docker exec -it clab-pg-lab-haproxy1 haproxy -f /usr/local/etc/haproxy/haproxy.cfg -d" &

# haproxy2
echo -n "Starting HAProxy2"
kitty --title="haproxy2" bash -c "docker exec -it clab-pg-lab-haproxy2 haproxy -f /usr/local/etc/haproxy/haproxy.cfg -d" &

echo -n "Waiting for HAProxy"
until docker port clab-pg-lab-haproxy1 2>/dev/null | grep -q 5432; do
  echo -n "."
  sleep 1
done
echo "Ok"

echo -n "Configuring Zabbix network..."
docker network rm zabbix-net 2>/dev/null
docker network create zabbix-net --subnet=172.20.24.0/24
docker network connect zabbix-net clab-pg-lab-zabbix-server --ip 172.20.24.20
docker network connect zabbix-net clab-pg-lab-zabbix-db --ip 172.20.24.21
docker network connect zabbix-net clab-pg-lab-zabbix-web --ip 172.20.24.22
echo "Ok"

echo -n "Starting Zabbix Agent 2 on node1..."
docker exec -u root clab-pg-lab-node1 bash -c '
  mkdir -p /run/zabbix
  pkill -9 zabbix_agent2 2>/dev/null
  rm -f /var/run/zabbix/zabbix_agent2.pid 2>/dev/null
  /usr/sbin/zabbix_agent2 -c /etc/zabbix/zabbix_agent2.conf &
' 2>/dev/null
echo "Ok"

ES_IP=$(docker inspect clab-pg-lab-elasticsearch | grep IPAddress | awk -F'"' '{print $4}' | head -1)
echo "Elasticsearch IP: $ES_IP"

sed -i "s/host .*/host ${ES_IP}/" fluentd/fluentd.conf
docker restart clab-pg-lab-fluentd

ES_IP=$(docker inspect clab-pg-lab-elasticsearch | grep IPAddress | awk -F'"' '{print $4}' | head -1)

docker stop clab-pg-lab-kibana 2>/dev/null
docker rm clab-pg-lab-kibana 2>/dev/null

docker run -d \
  --name clab-pg-lab-kibana \
  --network clab \
  --ip 172.20.20.100 \
  -e ELASTICSEARCH_HOSTS="http://${ES_IP}:9200" \
  -p 5601:5601 \
  docker.elastic.co/kibana/kibana:9.0.0

echo ""
echo "Check:  docker exec clab-pg-lab-node1 patronictl -c /etc/patroni.yml list"
echo "Write:  psql -h localhost -p 5432 -U postgres"
echo "Read:   psql -h localhost -p 5433 -U postgres"
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000 (admin/admin)"
echo "Zabbix:     http://localhost:8080 (Admin/zabbix)"
echo "Kibana:     http://localhost:5601"
echo "Jaeger:     http://localhost:16686"
echo "HAProxy Stats: http://localhost:8404/stats (admin/admin)"
