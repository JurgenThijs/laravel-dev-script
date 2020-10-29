# laravel-dev-script
This script creates a Laravel project for developing on your local machine. It also creates a MySQL database, virutalhost and SSL certificate

## My setup
I created this script for usage on my Centos 8 develop machine and local dev webserver.

My machine, a Centos 8, is connected to my modem of my ISP (https://www.telenet.be). This modem is also my router where i created a portforward to my develop machine which has a fixed local IP. There is an Apache server running with PHP 7.4 and a MariaDB-server. Composer, NodeJS, Yarn, Git and Certbot.

On my domain name I create a subdomain that points to my local public IP of my modem.

## Usage

./laraveldev.sh project

## Prerequisites
On my Centos 8 machine the following software is installed:
 - PHP (currently 7.4.12)
 - MySQL/MariaDB
 - Apache (httpd)
 - Composer => https://getcomposer.org/download/
 - Nodejs & yarn => https://nodejs.org/en/ & https://yarnpkg.com/getting-started/install
 - Git => https://git-scm.com/doc
 - Certbot => https://certbot.eff.org
 
 ## Script
 
It creates a Laravel project, sets some variables. Creates a database and saves the credentials in the .env files. Installs some extra packages. I also create a virtualhost and an SSL of Let's Encrypt
