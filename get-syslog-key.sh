#!/bin/sh

ssh_opts="-o ConnectTimeout=3"

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <ssh_args>"
    echo
    echo "Example: $0 \$USER@192.168.1.20"
    exit 1
fi >&2

ssh_args=("$@")

function get_mac() {
    ssh $ssh_opts "${ssh_args[@]}" mca-cli-op info | grep -i "mac address" | cut -d: -f2- | tr -d ' '
}

function get_syslog_key() {
    ssh $ssh_opts "${ssh_args[@]}" cat /etc/sysinit/syslog.conf | grep -e '/sbin/logread.*-E' | sed -e 's/.* -E //' -e 's/ .*//'
}

echo "$(get_mac) $(get_syslog_key)"
