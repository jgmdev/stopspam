#!/bin/bash

clear

echo "Uninstalling Stop Spam"

if [ -e '/etc/init.d/stopspam' ]; then
    echo; echo -n "Deleting init service..."
    UPDATERC_PATH=`whereis update-rc.d`
    if [ "$UPDATERC_PATH" != "update-rc.d:" ]; then
        service stopspam stop > /dev/null 2>&1
        update-rc.d stopspam remove > /dev/null 2>&1
    fi
    rm -f /etc/init.d/stopspam
    echo -n ".."
    echo " (done)"
fi

if [ -e '/usr/lib/systemd/system/stopspam.service' ]; then
    echo; echo -n "Deleting systemd service..."
    SYSTEMCTL_PATH=`whereis update-rc.d`
    if [ "$SYSTEMCTL_PATH" != "systemctl:" ]; then
        systemctl stop stopspam > /dev/null 2>&1
        systemctl disable stopspam > /dev/null 2>&1
    fi
    rm -f /usr/lib/systemd/system/stopspam.service
    echo -n ".."
    echo " (done)"
fi

echo -n "Deleting script files..."
if [ -e '/usr/bin/stopspam' ]; then
    rm -f /usr/bin/stopspam
    echo -n "."
fi

if [ -d '/usr/share/doc/stopspam' ]; then
    rm -rf /usr/share/doc/stopspam
    echo -n "."
fi
echo " (done)"

echo -n "Removing man page..."
if [ -e '/usr/share/man/man1/stopspam.1' ]; then
    rm -f /usr/share/man/man1/stopspam.1
    echo -n "."
fi
if [ -e '/usr/share/man/man1/stopspam.1.gz' ]; then
    rm -f /usr/share/man/man1/stopspam.1.gz
    echo -n "."
fi
echo " (done)"

echo; echo "Uninstall Complete!"; echo
