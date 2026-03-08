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
REPLICA2_CONTAINER="socnet-db-replica-quorum"
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

# Обновляем конфигурацию мастера для КВОРУМНОЙ репликации
echo "Настраиваем мастер для кворумной репликации..."

# Устанавливаем synchronous_standby_names для кворумной репликации
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "ALTER SYSTEM SET synchronous_standby_names = '2 (dbslave, dbslave2)';"
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "ALTER SYSTEM SET wal_level = 'replica';"
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "ALTER SYSTEM SET max_wal_senders = 10;"
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "ALTER SYSTEM SET synchronous_commit = 'remote_apply';"
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "SELECT pg_reload_conf();"

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

# Проверяем, что кворумная репликация настроена
echo "Проверяем параметры репликации на мастере:"
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "SHOW synchronous_standby_names;"
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "SHOW synchronous_commit;"

echo "Создаём директорию для бэкапа на мастере..."
docker exec -i $MASTER_CONTAINER rm -rf /dbslave 2>/dev/null || true
docker exec -i $MASTER_CONTAINER mkdir -p /dbslave

echo "Выполняем pg_basebackup для создания начального бэкапа..."
docker exec -i $MASTER_CONTAINER pg_basebackup -h localhost -D /dbslave -U replicator -v -P --wal-method=stream || {
  echo "Ошибка при выполнении pg_basebackup. Убедитесь, что пользователь replicator существует и имеет права."
  exit 1
}

# Копируем данные в обе директории реплик
mkdir -p "$REPLICA1_DATA_DIR"
mkdir -p "$REPLICA2_DATA_DIR"
echo "Копируем данные в директорию первой реплики..."
docker cp $MASTER_CONTAINER:/dbslave/. "$REPLICA1_DATA_DIR"
echo "Копируем данные в директорию второй реплики..."
docker cp $MASTER_CONTAINER:/dbslave/. "$REPLICA2_DATA_DIR"

# Настройка первой реплики
echo "Настраиваем первую реплику..."
touch "$REPLICA1_DATA_DIR/standby.signal"
cat > "$REPLICA1_DATA_DIR/postgresql.auto.conf" << EOF
primary_conninfo = 'host=$MASTER_CONTAINER port=5432 user=replicator password=password123 application_name=$REPLICA1_SERVICE'
recovery_target_timeline = 'latest'
port = 5432
EOF

# Настройка второй реплики
echo "Настраиваем вторую реплику..."
touch "$REPLICA2_DATA_DIR/standby.signal"
cat > "$REPLICA2_DATA_DIR/postgresql.auto.conf" << EOF
primary_conninfo = 'host=$MASTER_CONTAINER port=5432 user=replicator password=password123 application_name=$REPLICA2_SERVICE'
recovery_target_timeline = 'latest'
port = 5432
EOF

echo "Реплики настроены"
echo "Удаляем старые контейнеры, если они существуют..."
docker rm -f socnet-db-replica socnet-db-replica-quorum 2>/dev/null || true

echo "Запускаем реплики через docker-compose..."
docker-compose -f docker-compose.yml up -d --build --remove-orphans --quiet-pull || { echo "Ошибка при запуске реплик"; exit 1; }

echo "Ожидание запуска реплик..."
sleep 15

# Проверяем статус репликации несколько раз с интервалом
for i in {1..3}; do
  echo "Проверка статуса репликации (попытка $i):"
  docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "SELECT application_name, sync_state FROM pg_stat_replication;"
  sleep 5
done

# Проверяем параметры синхронизации
echo "Проверяем параметры синхронизации на мастере:"
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "SHOW synchronous_standby_names;"
docker exec -i $MASTER_CONTAINER psql -U postgres -d social_network -c "SHOW synchronous_commit;"

# Проверяем, запущены ли оба контейнера
echo "Проверяем запущенные контейнеры:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "$MASTER_CONTAINER|socnet-db-replica"

echo "Для детальной диагностики выполните:"
echo "docker logs socnet-db-replica-quorum"
echo "docker exec -it socnet-db-replica-quorum cat /var/lib/postgresql/data/postgresql.auto.conf"