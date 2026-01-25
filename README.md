## Развернуть проект
1) git clone git@github.com:ghosttim/socnet.git
2) cd socnet
3) cp .env.example .env
4) composer install


## Запуск
docker-compose up -d

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