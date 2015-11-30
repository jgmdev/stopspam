#!/bin/bash
##############################################################################
# Stop Spam version 0.1 Author: Jefferson González <jgmdev@gmail.com>        #
##############################################################################
# This program is distributed under the MIT License                          #
#                                                                            #
# The LICENSE file is located in the same directory as this program.         #
##############################################################################

CONF_PATH="/etc/stopspam"
CONF_PATH="${CONF_PATH}/"

# Name of file holding the ip list of spammers.
SPAM_IP_LIST="spam.ip.list"
BANS_IP_LIST="/etc/stopspam/bans.ip.list"

load_conf()
{
    CONF="${CONF_PATH}stopspam.conf"
    if [ -f "$CONF" ] && [ ! "$CONF" == "" ]; then
        source $CONF
    else
        head
        echo "\$CONF not found."
        exit 1
    fi
}

head()
{
    echo "Stop Spam version 0.1"
    echo "Copyright (C) 2014, Jefferson González <jgmdev@gmail.com>"
    echo
}

showhelp()
{
    head
    echo 'Usage: stopspam [OPTION]'
    echo
    echo 'OPTIONS:'
    echo '-h | --help: Show this help screen'
    echo '-d | --start: Initialize a daemon to monitor connections'
    echo '-s | --stop: Stop the daemon'
    echo '-t | --status: Show status of daemon and pid if currently running'
    echo '-b | --bans: View list of banned ip addresses'
    echo '-u | --update: Updates the spammers database file'
}

# Check if super user is executing the
# script and exit with message if not.
su_required()
{
    user_id=`id -u`

    if [ "$user_id" != "0" ]; then
        echo "You need super user priviliges for this."
        exit
    fi
}

log_msg()
{
    if [ ! -e /var/log/stopspam.log ]; then
        touch /var/log/stopspam.log
        chmod 0640 /var/log/stopspam.log
    fi

    echo "$(date +'[%Y-%m-%d %T]') $1" >> /var/log/stopspam.log
}

bans_list()
{
    if [ -e "$BANS_IP_LIST" ]; then
        cat "$BANS_IP_LIST"
    fi
}

# Unbans ip's after 10 minutes
clean_ban_list()
{
    current_unban_time=`date +"%s"`

    while read line; do
        if [ "$line" = "" ]; then
            continue
        fi

        ban_time=`echo "$line" | cut -d" " -f1`
        ip=`echo "$line" | cut -d" " -f2`

        if [ $current_unban_time -gt $ban_time ]; then
            if [ "$FIREWALL" = "apf" ]; then
                $APF -u "$ip"
            elif [ "$FIREWALL" = "csf" ]; then
                $CSF -dr "$ip"
            elif [ "$FIREWALL" = "iptables" ]; then
                $IPT -D INPUT -s "$ip" -j DROP
            fi

            log_msg "unbanned $ip"

            # remove the ip from the bans list
            grep -v "$ip" "$BANS_IP_LIST" > "$BANS_IP_LIST.tmp"
            rm "$BANS_IP_LIST"
            mv "$BANS_IP_LIST.tmp" "$BANS_IP_LIST"
        fi
    done < $BANS_IP_LIST
}

update_spam_list()
{
    let "HOURS=$(date +'%s') - $(date -r ${CONF_PATH}${SPAM_IP_LIST} +'%s')"
    let "HOURS=$HOURS / 60 / 60"

    DB_SIZE=$(ls -l "${CONF_PATH}${SPAM_IP_LIST}" | awk '{print $5}')

    if [ $HOURS -lt $UPDATE_INTERVAL ] && [ $DB_SIZE -gt 1 ]; then
        if [ $UPDATE_DB_INTERACTIVE -eq 1 ]; then
            echo "Database seems up to date..."
        fi

        return 0
    fi


    if [ "$SPAM_DB_URL" != "" ]; then
        mkdir -p /tmp/stopspam
        TMP_FILE=`mktemp -u /tmp/stopspam/db.XXXXXXXX`

        if [ $UPDATE_DB_INTERACTIVE -eq 1 ]; then
            echo "Starting database download..."
            wget -O "$TMP_FILE" --no-check-certificate "$SPAM_DB_URL"
        else
            wget -O "$TMP_FILE" --no-check-certificate "$SPAM_DB_URL" > /dev/null 2>&1
        fi

        # In case of download fail
        if [ "$?" != "0" ]; then
            if [ $UPDATE_DB_INTERACTIVE -eq 1 ]; then
                echo "Database download failed..."
            fi

            log_msg "error: failed to download spam database"
            rm -rf /tmp/stopspam
            return 1
        fi

        IS_ZIP=$(echo $SPAM_DB_URL | grep ".zip")

        if [ "$IS_ZIP" != "" ]; then
            unzip -p "$TMP_FILE" > "${CONF_PATH}${SPAM_IP_LIST}"
        else
            mv -f "$TMP_FILE" "${CONF_PATH}${SPAM_IP_LIST}"
        fi

        rm -rf /tmp/stopspam

        log_msg "spam database updated from $SPAM_DB_URL"

        if [ $UPDATE_DB_INTERACTIVE -eq 1 ]; then
            echo "Database updated!"
        fi
    fi
}

# Check active connections and ban if neccessary.
check_connections()
{
    su_required

    IP_LIST=$(netstat -ntu | \
        # Strip netstat heading
        tail -n +3 | \
        # Extract only the fifth column
        awk '{print $5}' | \
        # Strip port without affecting ipv6 addresses
        sed "s/:[0-9+]*$//g" | \
        # Sort addresses for uniq to work correctly
        sort | \
        # Group same occurrences of ip number
        uniq
    )

    IP_BAN=0

    for ip in $IP_LIST; do
        # Skip banned ip's
        ip_banned=$(grep "$ip" "$BANS_IP_LIST")
        if [ "$ip_banned" != "" ]; then
            continue
        fi

        ip_found=$(grep "$ip" "${CONF_PATH}${SPAM_IP_LIST}")

        if [ "$ip_found" != "" ]; then
            if [ "$FIREWALL" = "apf" ]; then
                $APF -d $ip
            elif [ "$FIREWALL" = "csf" ]; then
                $CSF -d $ip
            elif [ "$FIREWALL" = "iptables" ]; then
                $IPT -I INPUT -s $ip -j DROP
            fi

            IP_COUNTRY=$(whois $ip | grep -m 1 -i country | awk '{print $2}')

            # Connections are banned for 10 minutes to keep iptables clean
            current_time=`date +"%s"`
            echo "$(($current_time+600)) ${ip} ${IP_COUNTRY}" >> "$BANS_IP_LIST"

            log_msg "banned $ip from country $IP_COUNTRY"

            IP_BAN=1
        fi
    done
}

# Executed as a cleanup function when the daemon is stopped
on_daemon_exit()
{
    if [ -e /var/run/stopspam.pid ]; then
        rm -f /var/run/stopspam.pid
    fi

    exit 0
}

# Return the current process id of the daemon or 0 if not running
daemon_pid()
{
    if [ -e /var/run/stopspam.pid ]; then
        echo $(cat /var/run/stopspam.pid)

        return
    fi

    echo "0"
}

# Check if daemon is running.
# Outputs 1 if running 0 if not.
daemon_running()
{
    if [ -e /var/run/stopspam.pid ]; then
        running_pid=$(ps -A | grep stopspam | awk '{print $1}')

        if [ "$running_pid" != "" ]; then
            current_pid=$(daemon_pid)

            for pid_num in $running_pid; do
                if [ "$current_pid" = "$pid_num" ]; then
                    echo "1"
                    return
                fi
            done
        fi
    fi

    echo "0"
}

start_daemon()
{
    su_required

    if [ $(daemon_running) = "1" ]; then
        echo "stopspam daemon is already running..."
        exit 0
    fi

    # Create or clean ban list
    if [ ! -e "$BANS_IP_LIST" ]; then
        touch "$BANS_IP_LIST"
    fi

    echo "starting stopspam daemon..."

    nohup $0 -l > /dev/null 2>&1 &

    log_msg "daemon started"
}

stop_daemon()
{
    su_required

    if [ $(daemon_running) = "0" ]; then
        echo "stopspam daemon is not running..."
        exit 0
    fi

    echo "stopping stopspam daemon..."

    kill $(daemon_pid)

    while [ -e /var/run/stopspam.pid ]; do
        continue
    done

    log_msg "daemon stopped"
}

daemon_loop()
{
    su_required

    if [ $(daemon_running) = "1" ]; then
        exit 0
    fi

    echo "$$" > /var/run/stopspam.pid

    trap 'on_daemon_exit' INT
    trap 'on_daemon_exit' QUIT
    trap 'on_daemon_exit' TERM
    trap 'on_daemon_exit' EXIT

    detect_firewall

    # run clean_ban_list after 2 minutes of initialization
    ban_check_timer=`date +"%s"`
    ban_check_timer=$(($ban_check_timer+120))

    while true; do
        check_connections

        # unban expired ip's every 1 minute
        current_loop_time=`date +"%s"`
        if [ $current_loop_time -gt $ban_check_timer ]; then
            clean_ban_list
            ban_check_timer=`date +"%s"`
            ban_check_timer=$(($ban_check_timer+60))
        fi

        if [ $ENABLE_UPDATE -eq 1 ]; then
            update_spam_list
        fi

        sleep $DAEMON_FREQ
    done
}

daemon_status()
{
    current_pid=$(daemon_pid)

    if [ $(daemon_running) = "1" ]; then
        echo "stopspam status: running with pid $current_pid"
    else
        echo "stopspam status: not running"
    fi
}

detect_firewall()
{
    if [ "$FIREWALL" = "auto" ] || [ "$FIREWALL" = "" ]; then
        apf_where=`whereis apf`;
        csf_where=`whereis csf`;
        ipt_where=`whereis iptables`;

        if [ -e "$APF" ]; then
            FIREWALL="apf"
        elif [ -e "$CSF" ]; then
            FIREWALL="csf"
        elif [ -e "$IPT" ]; then
            FIREWALL="iptables"
        elif [ "$apf_where" != "apf:" ]; then
            FIREWALL="apf"
            APF="apf"
        elif [ "$csf_where" != "csf:" ]; then
            FIREWALL="csf"
            CSF="csf"
        elif [ "$ipt_where" != "iptables:" ]; then
            FIREWALL="iptables"
            IPT="iptables"
        else
            echo "error: No valid firewall found."
            log_msg "error: no valid firewall found"
            exit 1
        fi
    fi
}

# Default settings
APF="/usr/sbin/apf"
CSF="/usr/sbin/csf"
IPT="/sbin/iptables"
ENABLE_UPDATE=1
SPAM_DB_URL="http://www.stopforumspam.com/downloads/listed_ip_365.zip"
UPDATE_INTERVAL=48
FIREWALL="auto"
DAEMON_FREQ=3

# Load user settings
load_conf

UPDATE_DB_INTERACTIVE=0

while [ $1 ]; do
    case $1 in
        '-h' | '--help' | '?' )
            showhelp
            exit
            ;;
        '--start' | '-d' )
            start_daemon
            exit
            ;;
        '--stop' | '-s' )
            stop_daemon
            exit
            ;;
        '--status' | '-t' )
            daemon_status
            exit
            ;;
        '--loop' | '-l' )
            # start daemon loop, used internally by --start | -s
            daemon_loop
            exit
            ;;
        '--bans' | '-b' )
            echo "List of banned ip addresses."
            echo "============================"
            bans_list
            exit
            ;;
        '--update' | '-u' )
            su_required
            UPDATE_DB_INTERACTIVE=1
            update_spam_list
            exit
            ;;
        * )
            showhelp
            exit
            ;;
    esac

    shift
done


showhelp

exit 0
