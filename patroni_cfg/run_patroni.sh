#!/bin/bash

pkill -u postgres

chown -R postgres:postgres /var/lib/postgresql/data

exec /opt/patroni-env/bin/patroni /etc/patroni.yml
