#!/bin/bash

set -e

MASTER_CONTAINER="socnet-db"

# Конфигурация первой реплики
REPLICA1_DATA_DIR="./volumes/dbslave"
REPLICA1_CONTAINER="socnet-db-replica"
REPLICA1_SERVICE="dbslave"
REPLICA1_PORT="15432"

# Конфигурация второй реплики
REPLICA2_DATA_DIR="./volumes/dbslave2"
REPLICA2_CONTAINER="socnet-db-replica-async"
REPLICA2_SERVICE="dbslave2"
REPLICA2_PORT="25432"

# Остановка и удаление предыдущих реплик
if docker ps -a --format '{{.Names}}' | grep -q "^$REPLICA1_CONTAINER$"; then
  echo "Останавливаем и удаляем предыдущую реплику 1..."
  docker-compose -f docker-compose.yml rm -f --stop --volumes $REPLICA1_SERVICE
fi

if docker ps -a --format '{{.Names}}' | grep -q "^$REPLICA2_CONTAINER$"; then
  echo "Останавливаем и удаляем предыдущую реплику 2..."
  docker-compose -f docker-compose.yml rm -f --stop --volumes $REPLICA2_SERVICE
fi

# Очистка директорий реплик
if [ -d "$REPLICA1_DATA_DIR" ]; then
  echo "Очищаем директорию реплики 1: $REPLICA1_DATA_DIR"
  rm -rf "$REPLICA1_DATA_DIR"
fi

if [ -d "$REPLICA2_DATA_DIR" ]; then
  echo "Очищаем директорию реплики 2: $REPLICA2_DATA_DIR"
  rm -rf "$REPLICA2_DATA_DIR"
fi

# Создание пустых директорий
mkdir -p "$REPLICA1_DATA_DIR"
mkdir -p "$REPLICA2_DATA_DIR"

# Проверка, запущен ли мастер
if ! docker ps | grep -q "$MASTER_CONTAINER"; then
  echo "Ошибка: контейнер мастера $MASTER_CONTAINER не запущен. Запустите сначала setup_base.sh."
  exit 1
fi

#Обновляем конфигурацию мастера
docker exec -i $MASTER_CONTAINER sh -c 'cat > /usr/local/share/postgresql.conf.append << "EOF"
ssl = off
wal_level = replica
max_wal_senders = 10
synchronous_commit = off
EOF
'

echo "Перезапускаем мастер для применения конфигурации..."
docker restart $MASTER_CONTAINER
sleep 10

echo "Создаём пользователя replicator для репликации..."
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD 'password123';" || echo "Пользователь replicator уже существует, продолжаем."

echo "Обновляем pg_hba.conf для разрешения репликации..."
docker exec -i $MASTER_CONTAINER sh -c 'cat >> /var/lib/postgresql/data/pg_hba.conf << "EOF"

# Разрешить репликацию
host replication replicator 0.0.0.0/0 md5
host replication replicator ::/0 md5

# Разрешить подключения из Docker-сети
host all all 0.0.0.0/0 md5
host all all ::/0 md5
EOF'

echo "Перезапускаем мастер для применения pg_hba.conf..."
docker restart $MASTER_CONTAINER
sleep 15

echo "Создаём директорию для бэкапа на мастере..."
docker exec -i $MASTER_CONTAINER rm -rf /dbslave && docker exec -i $MASTER_CONTAINER mkdir -p /dbslave

echo "Выполняем pg_basebackup для создания начального бэкапа..."
docker exec -i $MASTER_CONTAINER pg_basebackup -h localhost -D /dbslave -U replicator -v -P --wal-method=stream || {
  echo "Ошибка при выполнении pg_basebackup. Убедитесь, что пользователь replicator существует и имеет права."
  exit 1
}

# Копируем данные в обе директории реплик
mkdir -p "$REPLICA1_DATA_DIR"
mkdir -p "$REPLICA2_DATA_DIR"
docker cp $MASTER_CONTAINER:/dbslave/. "$REPLICA1_DATA_DIR"
docker cp $MASTER_CONTAINER:/dbslave/. "$REPLICA2_DATA_DIR"

# Настройка первой реплики
echo "Настраиваем первую реплику..."
touch "$REPLICA1_DATA_DIR/standby.signal"
echo "primary_conninfo = 'host=socnet-db port=5432 user=replicator password=password123 application_name=$REPLICA1_SERVICE'" > "$REPLICA1_DATA_DIR/postgresql.auto.conf"
echo "#restore_command = 'cp /var/lib/postgresql/archive/%f %p'" >> "$REPLICA1_DATA_DIR/postgresql.auto.conf"
echo "recovery_target_timeline = 'latest'" >> "$REPLICA1_DATA_DIR/postgresql.auto.conf"
echo "promote_trigger_file = '/tmp/postgresql.trigger'" >> "$REPLICA1_DATA_DIR/postgresql.auto.conf"
echo "port = 5432" >> "$REPLICA1_DATA_DIR/postgresql.auto.conf"

# Настройка второй реплики
echo "Настраиваем вторую реплику..."
touch "$REPLICA2_DATA_DIR/standby.signal"
echo "primary_conninfo = 'host=socnet-db port=5432 user=replicator password=password123 application_name=$REPLICA2_SERVICE'" > "$REPLICA2_DATA_DIR/postgresql.auto.conf"
echo "#restore_command = 'cp /var/lib/postgresql/archive/%f %p'" >> "$REPLICA2_DATA_DIR/postgresql.auto.conf"
echo "recovery_target_timeline = 'latest'" >> "$REPLICA2_DATA_DIR/postgresql.auto.conf"
echo "promote_trigger_file = '/tmp/postgresql.trigger2'" >> "$REPLICA2_DATA_DIR/postgresql.auto.conf"
echo "port = 5432" >> "$REPLICA2_DATA_DIR/postgresql.auto.conf"

echo "Реплики настроены"
echo "Удаляем старые контейнеры, если они существуют..."
docker rm -f socnet-db-replica socnet-db-replica-async 2>/dev/null || true
docker-compose -f docker-compose.yml up -d --build --remove-orphans --quiet-pull || { echo "Ошибка при запуске реплик"; exit 1; }

echo "Реплики успешно запущены в асинхронном режиме"