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

function get_inform_key() {
    ssh $ssh_opts "${ssh_args[@]}" cat /etc/persistent/cfg/mgmt | grep authkey | cut -d= -f2
}

echo "$(get_mac) $(get_inform_key)"
