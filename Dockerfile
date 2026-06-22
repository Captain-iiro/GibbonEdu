FROM php:8.2-apache

LABEL maintainer="GibbonEdu Docker" \
      description="Gibbon - flexible, open source school management platform"

# Install system dependencies and PHP extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libicu-dev \
        libonig-dev \
        libzip-dev \
        libpng-dev \
        libxml2-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        unzip \
        git \
        locales \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        curl \
        intl \
        mbstring \
        gettext \
        pdo_mysql \
        gd \
        zip \
        xml \
        bcmath \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/fr_FR.UTF-8/s/^# //' /etc/locale.gen \
    && locale-gen fr_FR.UTF-8

# Enable Apache modules
RUN a2enmod rewrite headers expires remoteip \
    && echo 'RemoteIPHeader X-Forwarded-For' >> /etc/apache2/apache2.conf \
    && echo 'RemoteIPInternalProxy 10.0.0.0/8' >> /etc/apache2/apache2.conf \
    && echo 'SetEnvIf X-Forwarded-Proto https HTTPS=on' >> /etc/apache2/apache2.conf

# Allow .htaccess overrides
RUN sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Application
WORKDIR /var/www/html
COPY . .

# Install Composer dependencies (production)
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-security-blocking

# Create writable directories and set permissions
RUN mkdir -p resources/templates/cache var uploads \
    && chown -R www-data:www-data resources/templates/cache var uploads . \
    && chmod -R 755 resources/templates/cache var uploads

# Entrypoint script for config.php generation
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
