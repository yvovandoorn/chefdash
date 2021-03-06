#!/bin/bash

set -u
set -e
set -o pipefail

# Run this as root
if [[ $EUID -ne 0 ]]; then
	echo 'You must be root to install chefdash.' 2>&1
	exit 1
fi

# Install package dependencies
dpkg-query -l | grep python-software-properties || (apt-get update && apt-get install -y python-software-properties)
add-apt-repository 'deb http://nginx.org/packages/ubuntu/ precise nginx'
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ABF5BD827BD9BF62
apt-get update
apt-get -y install build-essential python-dev libevent-dev python-pip nginx ruby

# Install python dependencies
pip install -r requirements.txt

# Install chefdash
python setup.py install

# Upstart configuration
cp -f upstart/chefdash.conf /etc/init/

# nginx configuration
rm -f /etc/nginx/conf.d/default.conf
cp -f nginx/chefdash.conf /etc/nginx/conf.d/

# User

id -u chefdash &>/dev/null || useradd chefdash -r -d/var/lib/chefdash -m -s/bin/bash

# Config directory

mkdir -p /etc/chefdash

# Generate secret key and insert into the config file if necessary
# Do via function due to sendpipe causing havoc with the original method.
randpw(){
< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c${1:-32}
echo
}

secret_key=`randpw`
[ -f /etc/chefdash/chefdash.py ] || (echo -e "SECRET_KEY='$secret_key'\nLOG_FILE='/var/log/chefdash/chefdash.log'\nDEBUG=False" > /etc/chefdash/chefdash.py)
chmod 0600 /etc/chefdash/chefdash.py
chown -R chefdash:chefdash /etc/chefdash

# SSL certificates
if [ ! -f /var/lib/chefdash/ssl.crt ];
then
	openssl genrsa -out /var/lib/chefdash/ssl.key 2048
	openssl req -new -key /var/lib/chefdash/ssl.key -subj "/C=US/ST=Automation/L=AllTheThings/O=AutomateFTW/CN=`hostname -f`" -out /var/lib/chefdash/ssl.csr
	openssl x509 -req -days 7304 -in /var/lib/chefdash/ssl.csr -signkey /var/lib/chefdash/ssl.key -out /var/lib/chefdash/ssl.crt
	chown nginx:nginx /var/lib/chefdash/ssl.*
fi

# Log directory
mkdir -p /var/log/chefdash
chown -R chefdash:chefdash /var/log/chefdash

# Restart upstart services
service chefdash restart
service nginx restart
