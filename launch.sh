#!/bin/bash

TOPO_FILE="topology.yml"

echo "Starting lab"

# Containerlab
echo -n "Containerlab deployment"
sudo containerlab deploy -t "$TOPO_FILE"

# etcd
echo -n "Starting etcd"
kitty bash -c "docker exec -it clab-pg-lab-etcd bash -c 'apt-get update -qq && yes N | apt-get install -y -qq etcd && etcd --listen-client-urls http://[::]:2379 --advertise-client-urls http://clab-pg-lab-etcd:2379 --data-dir /tmp/etcd-data & exec bash'" &

echo -n "Waiting for etcd"
until docker exec clab-pg-lab-etcd etcdctl member list 2>/dev/null | grep -q "clientURLs"; do
  echo -n "."
  sleep 1
done
echo "Ok"

# node 1
echo -n "Starting Patroni node 1"
kitty --title="node1" bash -c "docker exec -it clab-pg-lab-node1 patroni /etc/patroni.yml" &

echo -n "Waiting for node1 Patroni API"
until docker exec clab-pg-lab-node1 timeout 1 bash -c 'echo > /dev/tcp/127.0.0.1/8008' 2>/dev/null; do
  echo -n "."
  sleep 1
done
echo -n "Ok"

# node 2
echo "Starting Patroni node2"
kitty --title="node2" bash -c "docker exec -it clab-pg-lab-node2 patroni /etc/patroni.yml" &

echo -n "Waiting for node2 Patroni API"
until docker exec clab-pg-lab-node2 timeout 1 bash -c 'echo > /dev/tcp/127.0.0.1/8008' 2>/dev/null; do
  echo -n "."
  sleep 1
done
echo -n "Ok"

# haproxy
echo -n "Starting HAProxy"
kitty --title="haproxy" bash -c "docker exec -it -u root clab-pg-lab-haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -d" &

echo -n "Waiting for HAProxy"
until docker port clab-pg-lab-haproxy 2>/dev/null | grep -q 5432; do
  echo -n "."
  sleep 1
done
echo -e "Ok"

echo "Check:  docker exec clab-pg-lab-node1 patronictl -c /etc/patroni.yml list"
echo "psql:   psql -h localhost -p 5432 -U postgres"
