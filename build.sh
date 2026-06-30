#!/bin/bash

echo "building docker images"

docker build -t my-etcd:1.0 -f dockerfiles/Dockerfile.etcd dockerfiles/
docker build -t my-fluentd:1.0 -f dockerfiles/Dockerfile.fluentd dockerfiles/
docker build -t my-haproxy:1.0 -f dockerfiles/Dockerfile.haproxy dockerfiles/
docker build -t my-node:1.0 -f dockerfiles/Dockerfile.node1 dockerfiles/

echo "built"
