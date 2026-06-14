# DBaaS Cluster Emulation

Cтенд отказоустойчивого кластера PostgreSQL в контейнеризированной среде Containerlab: автоматический failover, сетевая изоляция сервисов, мониторинг и нагрузочное тестирование.

## Архитектура

### PostgreSQL Cluster (Patroni + etcd)
Два узла PostgreSQL под управлением Patroni: Leader + Sync Standby. При отказе лидера реплика становится Leader автоматически. Patroni использует распределённый etcd-кластер из трёх узлов (кворум 2/3) как единый источник состояния.

### HAProxy
Два экземпляра HAProxy маршрутизируют клиентский трафик. Порт 5432 принимает запись и направляется на лидера. Порт 5433 принимает чтение и распределяется на реплику (round-robin). Роли определяются health-check'ами к Patroni REST API: `/master` возвращает 200 для лидера и 503 для реплики, `/replica` — наоборот.

### FRRouting/OSPF
Сервисы разнесены по четырём изолированным L2-подсетям:
- **172.20.21.0/24** — базы данных (node1, node2)
- **172.20.22.0/24** — haproxy1, haproxy2
- **172.20.23.0/24** — управление (etcd1, etcd2, etcd3)
- **172.20.24.0/24** — мониторинг (prometheus, grafana)

Маршрутизация между подсетями осуществляется роутером FRR с протоколом OSPF.

### Мониторинг (Prometheus + Grafana + Node Exporter)
Prometheus собирает метрики Patroni с порта 8008 обоих узлов PostgreSQL и системные метрики Node Exporter с порта 9100. Grafana визуализирует:

### Автоматизация развёртывания
Всё развёртывается одним Bash-скриптом `launch.sh`. Скрипт последовательно:
1. Поднимает контейнеры через Containerlab
2. Запускает FRR-роутер с OSPF
3. Формирует etcd-кластер из трёх узлов
4. Запускает Patroni на обоих узлах PostgreSQL 
5. Устанавливает и запускает HAProxy
6. Запускает Prometheus, Grafana и Node Exporter

## Быстрый старт

```bash
sudo containerlab destroy -t topology.yml
./launch.sh
