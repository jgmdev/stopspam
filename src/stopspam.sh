#!/bin/bash
##############################################################################
# Stop Spam version 0.1 Author: Jefferson González <jgmdev@gmail.com>        #
##############################################################################
# This program is distributed under the MIT License                          #
#                                                                            #
# The LICENSE file is located in the same directory as this program.         #
##############################################################################

SERVER_IP_LIST=$(ifconfig | \
    grep -E "inet6? " | \
    sed "s/addr: /addr:/g" | \
    awk '{print $2}' | \
    sed -E "s/addr://g" | \
    sed -E "s/\\/[0-9]+//g" | \
    xargs | \
    sed -e 's/ /|/g'
)

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
    echo "Stop Spam version 0.2"
    echo "Copyright (C) 2018, Jefferson González <jgmdev@gmail.com>"
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
    user_id=$(id -u)

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

# Gets a list of ip address to ignore with hostnames on the
# ignore.host.list resolved to ip numbers
# param1 can be set to 1 to also include the bans list
ignore_list()
{
    for the_host in $(grep -v "#" "${WHITE_IP_LIST}"); do
        host_ip=$(nslookup "$the_host" | tail -n +3 | grep "Address" | awk '{print $2}')

        # In case an ip is given instead of hostname
        # in the ignore.hosts.list file
        if [ "$host_ip" = "" ]; then
            echo "$the_host"
        else
            for ips in $host_ip; do
                echo "$ips"
            done
        fi
    done

    # Get ip's of ethernet interfaces to prevent blocking it self.
    #for iface_ip in $(ifconfig | grep "inet " | awk '{print $2}' | sed "s/addr://g"); do
    #    echo $iface_ip
    #done

    grep -v "#" "${WHITE_HOST_LIST}"

    if [ "$1" = "1" ]; then
        cut -d" " -f2 "${BANS_IP_LIST}"
    fi
}

# Bans a given ip using iptables or
# ip6tables for ipv6 connections.
# param1 The ip address to block
ban_ip()
{
    if ! echo "$1" | grep ":">/dev/null; then
        $IPT -I INPUT -s "$1" -j DROP
    else
        $IPT6 -I INPUT -s "$1" -j DROP
    fi

    if $SAVE_COUNTRY; then
        IP_COUNTRY=$(whois "$1" | grep -m 1 -i country | awk '{print $2}')

        current_time=$(date +"%s")

        echo "$((current_time+BAN_PERIOD)) $1 $IP_COUNTRY" >> "$BANS_IP_LIST"

        log_msg "banned $1 from country $IP_COUNTRY"
    else
        current_time=$(date +"%s")
        echo "$((current_time+BAN_PERIOD)) $1" >> "$BANS_IP_LIST"

        log_msg "banned $1"
    fi
}

# Unbans an ip.
# param1 The ip address
# param2 Optional amount of connections the unbanned ip did.
unban_ip()
{
    if [ "$1" = "" ]; then
        return 1
    fi

    if ! echo "$1" | grep ":">/dev/null; then
        $IPT -D INPUT -s "$1" -j DROP
    else
        $IPT6 -D INPUT -s "$1" -j DROP
    fi

    log_msg "unbanned $1"

    # remove the ip from the bans list
    grep -v "$1" "$BANS_IP_LIST" > "$BANS_IP_LIST.tmp"
    rm "$BANS_IP_LIST"
    mv "$BANS_IP_LIST.tmp" "$BANS_IP_LIST"

    return 0
}

bans_list()
{
    if [ -e "$BANS_IP_LIST" ]; then
        cat "$BANS_IP_LIST"
    fi
}

# Unbans ip's after the amount of seconds specified on $BAN_PERIOD
clean_ban_list()
{
    current_unban_time=$(date +"%s")

    while read line; do
        if [ "$line" = "" ]; then
            continue
        fi

        ban_time=$(echo "$line" | cut -d" " -f1)
        ip=$(echo "$line" | cut -d" " -f2)

        if [ "$current_unban_time" -gt "$ban_time" ]; then
            unban_ip "$ip"
        fi
    done < "$BANS_IP_LIST"
}

update_all()
{
    update_spam_list "$SPAM_IP_FULL_LIST" "$SPAM_DB_URL"

    if [ "$?" = "2" ]; then
        setup_spam_list "$SPAM_IP_FULL_LIST" "$SPAM_IP_LIST"
        append_spamhaus
    fi

    update_spam_list "$TOXIC_IP_LIST" "$TOXIC_DB_URL"
}

# Downloads a given url in txt or zip format and stores it
# param1 url of file to download
# param2 path to store the file
update_spam_list()
{
    HOURS="$(($(date +'%s') - $(date -r "$1" +'%s')))"
    HOURS="$((HOURS / 60 / 60))"

    DB_SIZE=$(ls -l "$1" | awk '{print $5}')

    if [ "$HOURS" -lt "$UPDATE_INTERVAL" ] && [ "$DB_SIZE" -gt 1 ]; then
        if [ "$UPDATE_DB_INTERACTIVE" -eq 1 ]; then
            echo "Database $1 seems up to date..."
        fi

        return 0
    fi

    if [ "$2" != "" ]; then
        mkdir -p /tmp/stopspam
        TMP_FILE=$(mktemp -u /tmp/stopspam/db.XXXXXXXX)

        if [ "$UPDATE_DB_INTERACTIVE" -eq 1 ]; then
            echo "Starting database download..."
            wget -O "$TMP_FILE" --no-check-certificate "$2"
        else
            wget -O "$TMP_FILE" --no-check-certificate "$2" > /dev/null 2>&1
        fi

        # In case of download fail
        if [ "$?" != "0" ]; then
            if [ "$UPDATE_DB_INTERACTIVE" -eq 1 ]; then
                echo "Database download failed..."
            fi

            log_msg "error: failed to download spam database at $2"
            rm -rf /tmp/stopspam
            return 1
        fi

        IS_ZIP=$(echo "$2" | grep ".zip")

        if [ "$IS_ZIP" != "" ]; then
            unzip -p "$TMP_FILE" > "$1"
        else
            mv -f "$TMP_FILE" "$1"
        fi

        rm -rf /tmp/stopspam

        log_msg "$1 updated from $2"

        if [ "$UPDATE_DB_INTERACTIVE" -eq 1 ]; then
            echo "Database $1 updated!"
        fi
    fi

    return 2
}

append_spamhaus()
{
    if ! $ENABLE_SPAMHAUS; then
        return 0
    fi

    TMP_FILE=$(mktemp -u /tmp/stopspamsh.XXXXXXXX)

    if [ "$UPDATE_DB_INTERACTIVE" -eq 1 ]; then
        echo "Starting spamhaus drop list download..."
        wget -O "$TMP_FILE" --no-check-certificate "$SPAMHAUS_DROP"
        cat "$TMP_FILE" >> "$SPAM_IP_LIST"

        echo "Starting spamhaus drop list download..."
        wget -O "$TMP_FILE" --no-check-certificate "$SPAMHAUS_DROPV6"
        cat "$TMP_FILE" >> "$SPAM_IP_LIST"

        echo "Starting spamhaus drop list download..."
        wget -O "$TMP_FILE" --no-check-certificate "$SPAMHAUS_EDROP"
        cat "$TMP_FILE" >> "$SPAM_IP_LIST"
    else
        wget -O "$TMP_FILE" --no-check-certificate "$SPAMHAUS_DROP" > /dev/null 2>&1
        cat "$TMP_FILE" >> "$SPAM_IP_LIST"

        wget -O "$TMP_FILE" --no-check-certificate "$SPAMHAUS_DROPV6" > /dev/null 2>&1
        cat "$TMP_FILE" >> "$SPAM_IP_LIST"

        wget -O "$TMP_FILE" --no-check-certificate "$SPAMHAUS_EDROP" > /dev/null 2>&1
        cat "$TMP_FILE" >> "$SPAM_IP_LIST"
    fi

    rm "$TMP_FILE"
}

# Use the $SPAM_IP_FULL_LIST to generate the $SPAM_IP_LIST taking
# in consideration the value of $MIN_SPAM_REPORTS.
setup_spam_list()
{
    cut -d"," -f1-2 < "$1" | \
        sed 's/"//g; s/,/ /g' | \
        awk "{ if (\$2 >= ${MIN_SPAM_REPORTS}) print \$1; }" > "$2"
}

# Check active connections and ban if neccessary.
check_connections()
{
    su_required

    whitelist=$(ignore_list "1")

    # Get spam connections
    IP_LIST=$(ss -Hntu state connected | \
        # Extract only the fifth column
        awk '{print $6}' | \
        # Sort addresses for uniq to work correctly
        sort | \
        # Unite same occurrences of ip for faster processing by next commands
        uniq | \
        # Strip port and [ ] brackets
        sed -E "s/\\[//g; s/\\]//g; s/:[0-9]+\$//g" | \
        # Only leave non whitelisted, we add ::1 to ensure -v works for ipv6
        grepcidr -v -e "$SERVER_IP_LIST $whitelist 127.0.0.1 ::1" 2>/dev/null | \
        # Only leave spammer ip's
        grepcidr -f "$SPAM_IP_LIST" -e "$(cat "TOXIC_IP_LIST")" 2>/dev/null
    )

    for ip in $IP_LIST; do
        if [ "$ip" != "" ]; then
            ban_ip "$ip"
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
        running_pid=$(pgrep stopspam)

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

    if [ "$(daemon_running)" = "1" ]; then
        echo "stopspam daemon is already running..."
        exit 0
    fi

    # Create or clean ban list
    if [ ! -e "$BANS_IP_LIST" ]; then
        touch "$BANS_IP_LIST"
    fi

    if [ ! -e "$SPAM_IP_FULL_LIST" ]; then
        touch "$SPAM_IP_FULL_LIST"
    fi

    if [ ! -e "$TOXIC_IP_LIST" ]; then
        touch "$TOXIC_IP_LIST"
    fi

    echo "starting stopspam daemon..."

    nohup "$0" -l > /dev/null 2>&1 &

    log_msg "daemon started"
}

stop_daemon()
{
    su_required

    if [ "$(daemon_running)" = "0" ]; then
        echo "stopspam daemon is not running..."
        exit 0
    fi

    echo "stopping stopspam daemon..."

    kill "$(daemon_pid)"

    while [ -e /var/run/stopspam.pid ]; do
        continue
    done

    log_msg "daemon stopped"
}

daemon_loop()
{
    su_required

    if [ "$(daemon_running)" = "1" ]; then
        exit 0
    fi

    echo "$$" > /var/run/stopspam.pid

    trap 'on_daemon_exit' INT
    trap 'on_daemon_exit' QUIT
    trap 'on_daemon_exit' TERM
    trap 'on_daemon_exit' EXIT

    # run clean_ban_list after 2 minutes of initialization
    ban_check_timer=$(date +"%s")
    ban_check_timer=$((ban_check_timer+120))

    while true; do
        check_connections

        # unban expired ip's every 10 minute
        current_loop_time=$(date +"%s")
        if [ "$current_loop_time" -gt "$ban_check_timer" ]; then
            clean_ban_list
            ban_check_timer=$(date +"%s")
            ban_check_timer=$((ban_check_timer+600))
        fi

        if $ENABLE_UPDATE; then
            update_all
        fi

        sleep "$DAEMON_FREQ"
    done
}

daemon_status()
{
    current_pid=$(daemon_pid)

    if [ "$(daemon_running)" = "1" ]; then
        echo "stopspam status: running with pid $current_pid"
    else
        echo "stopspam status: not running"
    fi
}

CONF_PATH="/etc/stopspam/"

# Default settings
ENABLE_UPDATE=true
SPAM_DB_URL="http://www.stopforumspam.com/downloads/listed_ip_365_ipv46_all.zip"
MIN_SPAM_REPORTS=3
TOXIC_DB_URL="http://www.stopforumspam.com/downloads/toxic_ip_cidr.txt"
UPDATE_INTERVAL=48
SAVE_COUNTRY=true
BAN_PERIOD=600
DAEMON_FREQ=3

# Load user settings
load_conf

UPDATE_DB_INTERACTIVE=0

while [ "$1" ]; do
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
            update_all
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
