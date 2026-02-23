#!/bin/bash

# Остановка и удаление существующих контейнеров
echo "Останавливаем работающие контейнеры..."
docker-compose down
if [ $? -ne 0 ]; then
  echo "Ошибка при остановке контейнеров"
  exit 1
fi
echo "Контейнеры остановлены."

# Проверка версии docker-compose
echo "Проверяем версию docker-compose..."
docker-compose -v
if [ $? -ne 0 ]; then
  echo "Ошибка при проверке версии docker-compose"
  exit 1
fi

# Запуск контейнеров в фоновом режиме
echo "Запускаем контейнеры..."
docker-compose up -d
if [ $? -ne 0 ]; then
  echo "Ошибка при запуске контейнеров"
  exit 1
fi
echo "Контейнеры запущены."

# Ожидание запуска базы данных
echo "Ожидаем запуска базы данных..."
sleep 15

# Параметры подключения к базе данных
HOST="localhost"
PORT="5432"
DB_NAME="social_network"
USER="postgres"
PASSWORD="password123"

# Выполнение SQL-файлов через docker exec
# Используем имя сервиса 'db', так как это имя контейнера в сети Docker
echo "Выполняем init.sql — создание таблиц..."
docker exec -i socnet-db psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB_NAME" < "./sql/init.sql"
if [ $? -ne 0 ]; then
  echo "Ошибка при выполнении init.sql"
  exit 1
fi
echo "Таблицы созданы."

echo "Выполняем generate_data.sql — наполнение данными..."
docker exec -i socnet-db psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB_NAME" < "./sql/generate_data.sql"
if [ $? -ne 0 ]; then
  echo "Ошибка при выполнении generate_data.sql"
  exit 1
fi
echo "Данные добавлены."

echo "Выполняем create_index.sql — создание индексов..."
docker exec -i socnet-db psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB_NAME" < "./sql/create_index.sql"
if [ $? -ne 0 ]; then
  echo "Ошибка при выполнении create_index.sql"
  exit 1
fi
echo "Индексы созданы."

echo "База ��анных инициализирована и заполнена."
