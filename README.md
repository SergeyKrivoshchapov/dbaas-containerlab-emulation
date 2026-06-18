# DBaaS Cluster Emulation

Cтенд отказоустойчивого кластера PostgreSQL в контейнеризированной среде Containerlab: автоматический failover, сетевая изоляция сервисов, мониторинг и нагрузочное тестирование.

# Стек
Категория	Технологии
Контейнеризация	Docker, Containerlab
СУБД	PostgreSQL
Отказоустойчивость	Patroni
DCS	etcd (кластер из 3 узлов)
Балансировка	HAProxy (read/write splitting)
Маршрутизация	FRRouting, OSPF
Мониторинг	Prometheus, Grafana, Node Exporter
Нагрузочное тестирование	Locust
Автоматизация	 Bash

## Архитектура

**PostgreSQL Cluster (Patroni + etcd)** — два узла PostgreSQL под управлением Patroni: Leader + Sync Standby. При отказе лидера реплика повышается до лидер автоматически. Patroni использует распределённый etcd-кластер из трёх узлов (кворум 2/3) как единый источник состояния.

**Маршрутизация трафика (HAProxy)** — два экземпляра HAProxy. Порт 5432 — запись на лидера. Порт 5433 — чтение на реплику, при недоступности реплик запросы автоматически переключаются на лидер (backup). Роли определяются health-check'ами к Patroni REST API.

**Сетевая изоляция (FRRouting/OSPF)** — сервисы разнесены по четырём изолированным подсетям с динамической маршрутизацией через OSPF. При расширении топологии достаточно добавить интерфейс на роутере и анонсировать сеть.

**Мониторинг (Prometheus + Grafana + Node Exporter)** — Prometheus собирает метрики Patroni и системные метрики. Grafana визуализирует роли узлов, репликационный лаг, WAL, версии компонентов, системные ресурсы.

**Нагрузочное тестирование (Locust + pgbench)** — нагрузочное тестирование сценариями Locust с разделением чтения/записи и автоматическим переподключением при failover. 

Всё развёртывается Bash-скриптом. Соответствующая инструкция приведена ниже.

## Быстрый старт

```bash
    sudo containerlab destroy -t topology.yml
    ./launch.sh
```


# Мониторинг

    Grafana: http://localhost:3000 (admin / admin)
    Prometheus: http://localhost:9090


# Load tests (Locust)

```bash
    locust -f locustfile.py
```

# Результаты проведения нагрузочного тестирования в Locust

<img width="1486" height="699" alt="image" src="https://github.com/user-attachments/assets/4fa07bb2-fc9d-4d65-a702-3a7e588265c6" />
<img width="1498" height="654" alt="image" src="https://github.com/user-attachments/assets/f71c5a53-a35f-45e4-84f3-e0952bf90a83" />
Состояние кластера в норме: node1 лидер, node2 синхронная реплика, лаг 0, WAL без отставания.
<img width="1536" height="287" alt="image" src="https://github.com/user-attachments/assets/63672c9f-df37-4cd5-8280-a4ad5d094b48" />
<img width="1483" height="902" alt="image" src="https://github.com/user-attachments/assets/0813e891-7f33-486f-b683-52e6cbf2ee21" />
Нагрузка 50 пользователей до отказа: Ошибок нет, RPS 40. Чтение через порт 5433, запись через 5432.

**После остановки Patroni на node1 (искусственный тест failover):** 
node2 стал лидером, node1 недоступен.
После восстановления кластера: Автоматическое переподключение к новому лидеру.
При failover 95-й процентиль задержки вырос до 3000 мс — это время, которое потребовалось etcd для обнаружения потери лидера и Patroni для повышения реплики.

<img width="1473" height="686" alt="image" src="https://github.com/user-attachments/assets/516c5c86-1744-4461-a2a3-9ad5437b1e14" />
<img width="1477" height="644" alt="image" src="https://github.com/user-attachments/assets/60291ac1-81c2-4ecd-afe1-978356bbbd60" />
<img width="1509" height="879" alt="image" src="https://github.com/user-attachments/assets/5ae417be-cac3-4aca-9613-c619330db324" />
<img width="1532" height="267" alt="image" src="https://github.com/user-attachments/assets/bd3a68ed-0504-4368-b9d6-332e1a8e8f68" />


