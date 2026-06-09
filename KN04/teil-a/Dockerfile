FROM php:8.0-apache

WORKDIR /var/www/html

COPY info.php .
COPY db.php .

RUN docker-php-ext-install mysqli

EXPOSE 80
