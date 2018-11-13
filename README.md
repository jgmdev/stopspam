# Stop Spam

Anti-spam system that helps minimize the amount of spammers that
connect to your server by banning their ip's using one of the ip text databases
provided by [**stopforumspam**](http://www.stopforumspam.com/downloads).
Also the script can optionally fetch the
[spamhaus.org](https://www.spamhaus.org/drop/) ip list text files.
**Stop Spam** also keeps this text databases updated by periodically
downloading latest version from the  website or any other url that
you set on the configuration file.

To keep the iptable rules minimal, the script bans every ip that is found
to be used for spamming for a predefined period of 10 minutes. After
the 10 minutes are due the ip is unbanned in order to minimize the
amount of rules actively used.

### Features

* Auto updates the spam ip database
* On the fly banning of spam ip's
* Keeps iptable rules clean
* Whitelisting of ip's and hosts
* IPv6 support

## Installation

As root user execute the following commands:

```shell
wget https://github.com/jgmdev/stopspam/archive/master.zip
unzip master.zip
cd stopspam-master
./install.sh
```

## Uninstallation

As root user execute the following commands:

```shell
cd stopspam-master
./uninstall.sh
```

## Usage

The installer will automatically detect if your system supports
init.d scripts or systemd services. If one of them is found
it will install apropiate files and start the stopspam script.

Once you have Stop Spam installed proceed to modify the config
files to fit your needs.

**/etc/stopspam/white.ip.list**

A list of ipv4 or ipv6 ip's to white list.

**/etc/stopspam/white.host.list**

A list of domains/hosts to white list.

**/etc/stopspam/stopspam.conf**

The behaviour of the stopspam script is modified by this configuration file.
For more details see **man stopspam** which has documentation of the
different configuration options.

After you modify the config files you will need to restart the daemon.
If running on systemd:

> systemctl restart stopspam

If running as classical init.d script:

> /etc/init.d/stopspam restart <br />
> or <br />
> service stopspam restart

## CLI Usage

**stopspam** [OPTION]

#### OPTIONS

**-h | --help:**

   Show the help screen.

**-d | --start:**

   Initialize a daemon to monitor connections.

**-s | --stop:**

   Stop the daemon.

**-t | --status:**

   Show status of daemon and pid if currently running.

**-b | --bans:**

   List banned ip addresses.

**-u | --update:**

   Updates the spammers database file.
