#!/bin/bash

# Author: Jurgen Thijs

# createproject.sh
#
# Sets up a laravel project for developing with certain settings
# It will create a mysql database with user
# Sets info in .env file
# Creates a Virtualhost in Apache
# Create a SSL Certificate from Let's Encrypt
#
# Prerequisites
# ===============
# composer installed globally => https://getcomposer.org/download/
# NodeJS => https://nodejs.org/en/
# httpd (Apache) => https://httpd.apache.org
# certbot => https://certbot.eff.org
# git => https://git-scm.com/doc

########################################################
#                                                      #
# Change the following variables for your own project  #
#                                                      #
########################################################

CODE_FOLDER=~/code
DEFAULT_DOMAIN='jt-productions.be'
TIMEZONE='Europe\/Brussels'
LANGUAGE='nl'
FAKER_LOCALE='nl_BE'

########################################################
#                                                      #
# Do NOT change anything below this                    #
#                                                      #
########################################################

clear
echo ""
echo "=============================="
echo "Creating a new Laravel project"
echo "=============================="
echo ""

# Checks if a project name is provided
if [[ $# -lt 1 ]]; then
    echo "usage: $0 projectname"
    exit 1
fi

PROJECT_NAME=$1

echo ""
echo "Installing Laravel"
echo "=================="
cd $CODE_FOLDER
/usr/local/bin/composer create-project --prefer-dist laravel/laravel ${PROJECT_NAME}
cd $PROJECT_NAME

# In phpunit.xml set remove the <!-- and --> for the DB_CONNECTION and DB_DATABASE
echo "Changing some settings in laravel"
echo "phpunit testing"
sed -i 's/<!-- //' phpunit.xml
sed -i 's/ -->//' phpunit.xml

# Change some settings in config/app.php
echo "app.php"
sed -i "s/'timezone' => 'UTC'/'timezone' => '${TIMEZONE}'/" config/app.php
sed -i "s/'locale' => 'en'/'locale' => '${LANGUAGE}'/" config/app.php
sed -i "s/'faker_locale' => 'en_US'/'faker_locale' => '${FAKER_LOCALE}'/" config/app.php
sed -i 's/QUEUE_CONNECTION=sync/QUEUE_CONNECTION=database/' .env

# Create migrations
echo "Creating some migrations"
php artisan -q queue:table
php artisan -q queue:failed-table
php artisan -q notifications:table

php artisan -q storage:link

# Create a cronjob
echo "Create cronjob"
crontab -l > ${PROJECT_NAME}
echo "* * * * * cd ${CODE_FOLDER}/${PROJECT_NAME} && php artisan schedule:run >> /dev/null 2>&1" >> ${PROJECT_NAME}
crontab ${PROJECT_NAME}
rm ${PROJECT_NAME}

#Creating Mysql
PWDDB="$(openssl rand -base64 12)"
DB="${PROJECT_NAME//[^a-zA-Z0-9]/_}"
MAINDB="${DB}_dev"
USERNAME="${PROJECT_NAME//[^a-zA-Z0-9]/_}"

echo ""
echo "MySQL"
echo "====="

#if /root/.my.cnf exists then it won't ask for root password
if [ -f /root/.my.cnf ]; then
	echo "Create database $MAINDB"
	mysql -e "CREATE DATABASE ${MAINDB} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
	echo "Create user"
	mysql -e "CREATE USER ${USERNAME}@localhost IDENTIFIED BY '${PWDDB}';"
	echo "Setting privilages"
	mysql -e "GRANT ALL PRIVILEGES ON ${MAINDB}.* TO '${USERNAME}'@'localhost';"
	mysql -e "FLUSH PRIVILEGES;"
# If /root/.my.cnf doesn't exist then it will ask for root password
else
	echo -n "Please enter root user MySQL password : "
	read -s ROOTPASSWD
        echo ""
	mysql -uroot -p${ROOTPASSWD} -e "DROP DATABASE IF EXISTS ${MAINDB};"
	mysql -uroot -p${ROOTPASSWD} -e "DROP USER IF EXISTS ${USERNAME}@localhost;"
	echo "Create database $MAINDB"
        mysql -uroot -p${ROOTPASSWD} -e "CREATE DATABASE ${MAINDB} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
        echo "Create user"
        mysql -uroot -p${ROOTPASSWD} -e "CREATE USER ${USERNAME}@localhost IDENTIFIED BY '${PWDDB}';"
        echo "Setting privilages"
        mysql -uroot -p${ROOTPASSWD} -e "GRANT ALL PRIVILEGES ON ${MAINDB}.* TO '${USERNAME}'@'localhost';"
        mysql -uroot -p${ROOTPASSWD} -e "FLUSH PRIVILEGES;"
fi

# Set database info in .env
echo "Configure database on .env"
sed -i "s/DB_USERNAME=root/DB_USERNAME=${USERNAME}/" .env
sed -i "s/DB_PASSWORD=/DB_PASSWORD=${PWDDB}/" .env
sed -i "s/DB_DATABASE=${PROJECT_NAME}/DB_DATABASE=${MAINDB}/" .env

# Adding some interesting packages
echo ""
echo "Adding some packages"
echo "===================="
echo "Installing barryvdh/laravel-ide-helper"
/usr/local/bin/composer require barryvdh/laravel-ide-helper --dev
echo "Installing livewire/livewire"
/usr/local/bin/composer require livewire/livewire

# Migrate all migrations to database
echo "Migrating tables to database"
php artisan -q migrate

## installing NodeJS
echo ""
echo "Installing Nodejs"
echo "================="
npm install && npm run dev

echo "Setting premissions"
sudo chmod -R 777 storage
sudo chmod -R 777 bootstrap/cache

# Create a default git repo
echo ""
echo "Git"
echo "==="
echo "Create Github actions"
mkdir -p .github/workflows/
touch .github/workflows/run-tests.yml
cat <<EOT >> .github/workflows/run-tests.yml
name: Tests

on: [ push ]

jobs:
  tests:
    name: Run tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v1

      - name: Cache composer dependencies
        uses: actions/cache@v1
        with:
          path: vendor
          key: composer-\${{ hashFiles('composer.lock') }}

      - name: Run composer install
        run: composer install -n --prefer-dist
        env:
          APP_ENV: testing

      - name: Prepare Laravel Application
        run: |
          cp .env.example .env
          php artisan key:generate

      - name: Run npm
        run: npm install && npm run dev

      - name: Run tests
        run: ./vendor/bin/phpunit
        env:
          APP_ENV: testing

      - name: Upload artifacts
        uses: actions/upload-artifact@master
        if: failure()
        with:
          name: Logs
          path: ./storage/logs
EOT

echo "Create Gitlab CI"
cp .env.example .env.example.gitlab
sed -i "s/DB_USERNAME=root/DB_USERNAME='ohdear_ci'" .env.example.gitlab
sed -i "s/DB_PASSWORD=/DB_PASSWORD='ohdear_secret'/" .env.example.gitlab
sed -i "s/DB_DATABASE=${PROJECT_NAME}/DB_DATABASE='ohdear_ci'/" .env.example.gitlab

touch .gitlab-ci.yml
cat <<EOT >> .gitlab-ci.yml
stages:
  - preparation
  - building
  - testing
  - security

image: edbizarro/gitlab-ci-pipeline-php:7.4-alpine

variables:
  MYSQL_ROOT_PASSWORD: root
  MYSQL_USER: ohdear_ci
  MYSQL_PASSWORD: ohdear_secret
  MYSQL_DATABASE: ohdear_ci
  DB_HOST: mysql

composer:
  stage: preparation
  script:
    - php -v
    - composer install --prefer-dist --no-ansi --no-interaction --no-progress --no-scripts
    - cp .env.example.gitlab .env
    - php artisan key:generate
  artifacts:
    paths:
      - vendor/
      - .env
    expire_in: 1 days
    when: always
  cache:
    paths:
      - vendor/

yarn:
  stage: preparation
  script:
    - yarn --version
    - yarn install --pure-lockfile
  artifacts:
    paths:
      - node_modules
    expire_in: 1 days
    when: always
  cache:
    paths:
      - node_modules

build-assets:
  stage: building
  dependencies:
    - composer
    - yarn
  script:
    - yarn --version
    - yarn run production --progress false
  artifacts:
    paths:
      - public/css
      - public/js
      - public/fonts
      - public/mix-manifest.json
    expire_in: 1 days
    when: always

db-seeding:
  stage: building
  services:
    - name: mysql:8.0
      command: [ "--default-authentication-plugin=mysql_native_password" ]
  dependencies:
    - composer
    - yarn
  script:
    - mysql --version
    - php artisan migrate:fresh --seed
    - mysqldump --host="\${DB_HOST}" --user="\${MYSQL_USER}" --password="\${MYSQL_PASSWORD}" "\${MYSQL_DATABASE}" > db.sql
  artifacts:
    paths:
      - storage/logs # for debugging
      - db.sql
    expire_in: 1 days
    when: always

phpunit:
  stage: testing
  services:
    - name: mysql:8.0
      command: [ "--default-authentication-plugin=mysql_native_password" ]

  dependencies:
    - build-assets
    - composer
    - db-seeding
  script:
    - php -v
    - sudo cp /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini /usr/local/etc/php/conf.d/docker-php-ext-xdebug.bak
    - echo "" | sudo tee /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
    - mysql --host="\${DB_HOST}" --user="\${MYSQL_USER}" --password="\${MYSQL_PASSWORD}" "\${MYSQL_DATABASE}" < db.sql
    - ./vendor/phpunit/phpunit/phpunit --version
    - php -d short_open_tag=off ./vendor/phpunit/phpunit/phpunit -v --coverage-text --stderr
    - sudo cp /usr/local/etc/php/conf.d/docker-php-ext-xdebug.bak /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
  artifacts:
    paths:
      - ./storage/logs # for debugging
    expire_in: 1 days
    when: on_failure

codestyle:
  stage: testing
  image: lorisleiva/laravel-docker
  script:
    - phpcs --standard=PSR2 --extensions=php app
  dependencies: [ ]

phpcpd:
  stage: testing
  script:
    - test -f phpcpd.phar || curl -L https://phar.phpunit.de/phpcpd.phar -o phpcpd.phar
    - php phpcpd.phar app/ --min-lines=50
  dependencies: [ ]
  cache:
    paths:
      - phpcpd.phar

sensiolabs:
  stage: security
  script:
    - test -d security-checker || git clone https://github.com/sensiolabs/security-checker.git
    - cd security-checker
    - composer install
    - php security-checker security:check ../composer.lock
  dependencies: [ ]
  cache:
    paths:
      - security-checker/
EOT

echo "Initialize Git"
git init -q
echo "Add whole project to staging"
git add .
echo "Commit"
git commit -m "Initialze Framework" -q

FQN="${PROJECT_NAME}.${DEFAULT_DOMAIN}"

echo ""
echo "Apache"
echo "======"
echo "First create your FQDN for this project!"
echo -n "Enter your FQDN [$FQN] : "
read FQDN

if [[ $FQDN == "" ]]; then
    FQDN="$FQN"
fi

sudo chmod -R 777 storage
sudo chmod -R 777 bootstrap/cache

echo "Creating apache conf file for http://${FQDN}"
sudo rm -rf /etc/httpd/conf.d/${PROJECT_NAME}*.conf
cat <<EOT >> ${PROJECT_NAME}_dev.conf
<VirtualHost *:80>
    DocumentRoot ${CODE_FOLDER}/${PROJECT_NAME}/public
    ServerName $FQDN

    ServerAdmin admin@jt-productions.be

    <Directory ${CODE_FOLDER}/${PROJECT_NAME}/public>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/${PROJECT_NAME}-dev.log
    CustomLog /var/log/httpd/${PROJECT_NAME}-dev-access.log combined
</VirtualHost>
EOT
sudo mv ${PROJECT_NAME}_dev.conf /etc/httpd/conf.d
sudo chown root:root /etc/httpd/conf.d/${PROJECT_NAME}_dev.conf
echo "Restart apache"
sudo systemctl restart httpd
echo "Create SSL certificiate with Let's Encrypt"
sudo certbot -d ${FQDN}
echo "Restart apache"
sudo systemctl restart httpd
