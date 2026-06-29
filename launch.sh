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

# etcd1
kitty --title="etcd1" bash -c "docker exec -it clab-pg-lab-etcd1 bash -c 'apt-get update -qq && yes N | apt-get install -y -qq etcd && etcd --name etcd1 --initial-cluster etcd1=http://clab-pg-lab-etcd1:2380,etcd2=http://clab-pg-lab-etcd2:2380,etcd3=http://clab-pg-lab-etcd3:2380 --initial-cluster-state new --initial-advertise-peer-urls http://clab-pg-lab-etcd1:2380 --listen-peer-urls http://[::]:2380 --listen-client-urls http://[::]:2379 --advertise-client-urls http://clab-pg-lab-etcd1:2379 --data-dir /tmp/etcd-data & exec bash'" &
sleep 10

# etcd2
kitty --title="etcd2" bash -c "docker exec -it clab-pg-lab-etcd2 bash -c 'apt-get update -qq && yes N | apt-get install -y -qq etcd && etcd --name etcd2 --initial-cluster etcd1=http://clab-pg-lab-etcd1:2380,etcd2=http://clab-pg-lab-etcd2:2380,etcd3=http://clab-pg-lab-etcd3:2380 --initial-cluster-state new --initial-advertise-peer-urls http://clab-pg-lab-etcd2:2380 --listen-peer-urls http://[::]:2380 --listen-client-urls http://[::]:2379 --advertise-client-urls http://clab-pg-lab-etcd2:2379 --data-dir /tmp/etcd-data & exec bash'" &
sleep 10

# etcd3
kitty --title="etcd3" bash -c "docker exec -it clab-pg-lab-etcd3 bash -c 'apt-get update -qq && yes N | apt-get install -y -qq etcd && etcd --name etcd3 --initial-cluster etcd1=http://clab-pg-lab-etcd1:2380,etcd2=http://clab-pg-lab-etcd2:2380,etcd3=http://clab-pg-lab-etcd3:2380 --initial-cluster-state new --initial-advertise-peer-urls http://clab-pg-lab-etcd3:2380 --listen-peer-urls http://[::]:2380 --listen-client-urls http://[::]:2379 --advertise-client-urls http://clab-pg-lab-etcd3:2379 --data-dir /tmp/etcd-data & exec bash'" &
sleep 10

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

# haproxy1 + haproxy2: установка iproute2 и IP
docker exec -u root clab-pg-lab-haproxy1 bash -c 'apt-get update -qq && apt-get install -y -qq iproute2 && ip addr add 172.20.22.21/24 dev eth0' 2>/dev/null
docker exec -u root clab-pg-lab-haproxy2 bash -c 'apt-get update -qq && apt-get install -y -qq iproute2 && ip addr add 172.20.22.22/24 dev eth0' 2>/dev/null

# node_exporter на node1 и node2
docker exec -u root clab-pg-lab-node1 bash -c 'apt-get update -qq && apt-get install -y -qq prometheus-node-exporter' 2>/dev/null
docker exec -u root clab-pg-lab-node2 bash -c 'apt-get update -qq && apt-get install -y -qq prometheus-node-exporter' 2>/dev/null
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

# zabbix
echo -n "Configuring Zabbix network"
docker network rm zabbix-net 2>/dev/null
docker network create zabbix-net --subnet=172.20.24.0/24
docker network connect zabbix-net clab-pg-lab-zabbix-server --ip 172.20.24.20
docker network connect zabbix-net clab-pg-lab-zabbix-db --ip 172.20.24.21
docker network connect zabbix-net clab-pg-lab-zabbix-web --ip 172.20.24.22
echo "Ok"

echo -n "Configuring Zabbix agent2 on node 1"

docker exec -u root clab-pg-lab-node1 bash -c '
  if ! command -v zabbix_agent2 &> /dev/null; then
    wget -q https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb -O /tmp/zabbix-release.deb
    dpkg -i /tmp/zabbix-release.deb 2>/dev/null
    apt-get update -qq
    apt-get install -y -qq zabbix-agent2
  fi

  echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
  sysctl -p

  cat > /etc/zabbix/zabbix_agent2.conf <<EOF
Server=0.0.0.0/0
ServerActive=172.20.20.11
Hostname=PostgreSQL-Cluster
ListenIP=0.0.0.0
Plugins.MongoDB.System.Disabled=true
Plugins.PostgreSQL.System.Disabled=true
EOF

  mkdir -p /run/zabbix
  pkill -9 zabbix_agent2 2>/dev/null
  rm -f /var/run/zabbix/zabbix_agent2.pid 2>/dev/null
  /usr/sbin/zabbix_agent2 -c /etc/zabbix/zabbix_agent2.conf &
' 2>/dev/null
echo "Ok"

echo ""

echo "Check:  docker exec clab-pg-lab-node1 patronictl -c /etc/patroni.yml list"
echo "Write:  psql -h localhost -p 5432 -U postgres"
echo "Read:   psql -h localhost -p 5433 -U postgres"
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000 (admin/admin)"
echo "Zabbix web: http://localhost:8080 (Admin/zabbix)"
