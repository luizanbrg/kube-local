# Utilisez une image Docker officielle pour PHP 7.4 avec Apache
FROM php:8.2.8-apache

# Installez les extensions PHP nécessaires
RUN docker-php-ext-install pdo_mysql

RUN apt-get update && apt-get install -y git unzip p7zip-full

# Installez Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copiez les fichiers de l'application dans le conteneur
COPY . /var/www/html/

# Installez les dépendances de l'application
RUN composer install

# Donnez les dossiers d'écriture de Laravel à www-data
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Modifiez la configuration d'Apache pour pointer vers le répertoire public
ENV APACHE_DOCUMENT_ROOT /var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Faites écouter Apache sur le port 8080 (port non privilégié)
RUN sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf \
 && sed -i 's/:80>/:8080>/' /etc/apache2/sites-available/000-default.conf

# Activez le module Apache Rewrite
RUN a2enmod rewrite

# Exposez le port 8080
EXPOSE 8080

# Exécutez le conteneur avec un utilisateur non privilégié
USER www-data
