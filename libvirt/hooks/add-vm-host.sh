#!/bin/bash

VM_NAME="$1"
ACTION="$2"
SUBACTION="$3"

DOMAIN=".local"
HOSTS_FILE="/etc/hosts.d/kvm-hosts"
HOSTNAME="${VM_NAME}${DOMAIN}"

mkdir -p "$(dirname "$HOSTS_FILE")"
touch "$HOSTS_FILE"

add_host() {
    grep -qw "$HOSTNAME" "$HOSTS_FILE" && exit 0

    for i in {1..10}; do
        VM_IP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1)
        [[ -z "$VM_IP" ]] && VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1)
        [[ -n "$VM_IP" ]] && break
        sleep 1
    done

    [[ -z "$VM_IP" ]] && exit 0
    echo "$VM_IP $HOSTNAME" >> "$HOSTS_FILE"
}

remove_host() {
    # robust removal (ignores spacing, tabs, trailing spaces)
    grep -vw "$HOSTNAME" "$HOSTS_FILE" > "${HOSTS_FILE}.tmp" && \
    mv "${HOSTS_FILE}.tmp" "$HOSTS_FILE"
}

case "$ACTION" in
    started|reconnect)
        add_host
        ;;
    stopped|shutdown|crashed|release)
        remove_host
        ;;
esac

exit 0
