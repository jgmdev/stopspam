#!/bin/bash

# Check for required dependencies
for dependency in unzip ss ifconfig iptables ip6tables whois wget awk sed grep pgrep grepcidr; do
    is_installed=`which $dependency`
    if [ "$is_installed" = "" ]; then
        echo "error: Required dependency '$dependency' is missing.";
        exit 1
    fi
done

if [ -e "$DESTDIR/usr/bin/stopspam" ]; then
    echo "Please un-install the previous version first"
    exit 0
fi

clear

if [ ! -d "$DESTDIR/etc/stopspam" ]; then
    mkdir -p "$DESTDIR/etc/stopspam"
fi

echo; echo 'Installing Stop Spam'; echo

if [ ! -e "$DESTDIR/etc/stopspam/stopspam.conf" ]; then
    echo -n 'Adding: /etc/stopspam/stopspam.conf...'
    cp config/stopspam.conf "$DESTDIR/etc/stopspam/stopspam.conf" > /dev/null 2>&1
    echo " (done)"
fi

if [ ! -e "$DESTDIR/etc/stopspam/white.ip.list" ]; then
    echo -n 'Adding: /etc/stopspam/white.ip.list...'
    cp config/white.ip.list "$DESTDIR/etc/stopspam/white.ip.list" > /dev/null 2>&1
    echo " (done)"
fi

if [ ! -e "$DESTDIR/etc/stopspam/white.host.list" ]; then
    echo -n 'Adding: /etc/stopspam/white.host.list...'
    cp config/white.host.list "$DESTDIR/etc/stopspam/white.host.list" > /dev/null 2>&1
    echo " (done)"
fi

if [ ! -e "$DESTDIR/etc/stopspam/spam.ip.list" ]; then
    echo -n 'Adding: /etc/stopspam/spam.ip.list...'
    touch "$DESTDIR/etc/stopspam/spam.ip.list" > /dev/null 2>&1
    echo " (done)"
fi

echo -n 'Adding: /usr/share/doc/stopspam/LICENSE...'
mkdir -p "$DESTDIR/usr/share/doc/stopspam/"
cp LICENSE "$DESTDIR/usr/share/doc/stopspam/LICENSE" > /dev/null 2>&1
echo " (done)"

echo -n 'Adding: /usr/bin/stopspam'
mkdir -p "$DESTDIR/usr/bin/"
cp src/stopspam.sh "$DESTDIR/usr/bin/stopspam" > /dev/null 2>&1
chmod 0755 /usr/bin/stopspam > /dev/null 2>&1
echo " (done)"

echo -n 'Adding man page...'
mkdir -p "$DESTDIR/usr/share/man/man1/"
cp man/stopspam.1 "$DESTDIR/usr/share/man/man1/stopspam.1" > /dev/null 2>&1
chmod 0644 "$DESTDIR/usr/share/man/man1/stopspam.1" > /dev/null 2>&1
echo " (done)"

if [ -d /etc/logrotate.d ]; then
    echo -n 'Adding logrotate configuration...'
    mkdir -p "$DESTDIR/etc/logrotate.d/"
    cp src/stopspam.logrotate "$DESTDIR/etc/logrotate.d/stopspam" > /dev/null 2>&1
    chmod 0644 "$DESTDIR/etc/logrotate.d/stopspam"
    echo " (done)"
fi

echo;

if [ -d /usr/lib/systemd/system ]; then
    echo -n 'Setting up systemd service...'
    mkdir -p "$DESTDIR/usr/lib/systemd/system/"
    cp src/stopspam.service "$DESTDIR/usr/lib/systemd/system/" > /dev/null 2>&1
    chmod 0755 "$DESTDIR/usr/lib/systemd/system/stopspam.service" > /dev/null 2>&1
    echo " (done)"
elif [ -d /etc/init.d ]; then
    echo -n 'Setting up init script...'
    mkdir -p "$DESTDIR/etc/init.d/"
    cp src/stopspam.initd "$DESTDIR/etc/init.d/stopspam" > /dev/null 2>&1
    chmod 0755 "$DESTDIR/etc/init.d/stopspam" > /dev/null 2>&1
    echo " (done)"
fi

echo; echo 'Installation has completed!'
echo 'Config files are located at /etc/stopspam/'
echo 'You should enable the stopspam service manually using systemctl or'
echo 'applicable init system for your linux distro.'

exit 0
