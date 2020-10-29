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
# yarn => https://yarnpkg.com/getting-started/install
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
TIMEZONE=Europe/Brussels
LANGUAGE=nl
FAKER_LOCALE=nl_BE

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
sed -i "s/'timezone' => 'UTC'/'timezone' => \'${TIMEZONE}\'/" config/app.php
sed -i "s/'locale' => 'en'/'locale' => \'${LANGUAGE}\'/" config/app.php
sed -i "s/'faker_locale' => 'en_US'/'faker_locale' => \'${FAKER_LOCALE}\'/" config/app.php
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
yarn

# Create a default git repo
echo ""
echo "Git"
echo "==="
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
