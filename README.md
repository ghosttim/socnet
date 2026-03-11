## Развернуть проект
1) git clone git@github.com:ghosttim/socnet.git
2) cd socnet
3) cp .env.example .env
4) Если будут запущены реплики, нужно в  .env установить APP_USE_REPLICATION=true
5composer install


## Запуск
Запустить проект 
```
./setup_base.sh
```
Запустить реплику в потоковом режиме
```
cd docker/replication/
./setup_async_replica.sh
```
Запустить реплику в синхронном режиме режиме
```
cd docker/replication/
./setup_sync_replica.sh
```
Запустить мониторинг
```
cd docker/monitoring
./setup-monitoring.sh
```

## User Registration
Endpoint: `POST /user/register`
```
{
"first_name": "John",
"second_name": "Doe",
"birthdate": "1990-01-01",
"biography": "Programming, reading, sports",
"city": "Moscow",
"password": "secretpassword123"
}
```
**Successful Response (200):**
```
{
"user_id": "5"
}
```

## User Authentication
Endpoint: `POST /login`
```
{
  "id": "1",
  "password": "secretpassword123"
}
```
**Successful Response (200):**
```
{
  "token": "e4d2e6b0-cde2-42c5-aac3-0b8316f21e58"
}
```

## Get User Profile
Endpoint: `GET /user/get/{id}`
```
Path Parameters:
id - User ID (required)
```
**Successful Response (200):**
```
{
  "id": "1",
  "first_name": "John",
  "second_name": "Doe",
  "birthdate": "1990-01-01",
  "biography": "Programming, reading, sports",
  "city": "Moscow"
}
```