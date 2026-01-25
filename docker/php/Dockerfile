FROM php:8.4-fpm-alpine

RUN apk add --no-cache postgresql-dev && \
    docker-php-ext-install pdo pdo_pgsql

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY . .

RUN composer install --optimize-autoloader

EXPOSE 9000

CMD ["php-fpm"]