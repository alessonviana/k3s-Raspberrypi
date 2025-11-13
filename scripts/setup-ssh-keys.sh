#!/bin/bash
# Script to configure SSH keys on Raspberry Pi machines

set -e

# This script uses hosts from the inventory
# Run: ./scripts/setup-ssh-keys.sh
# Or configure manually using the generated inventory

# Example hosts (adjust according to your inventory):
# HOSTS=(
#     "pi@192.168.2.111"  # master01
#     "pi@192.168.2.112"  # worker01
#     "pi@192.168.2.113"  # worker02
# )

# Read hosts from inventory if it exists
if [ -f "inventory/hosts.yml" ]; then
    echo "📋 Reading hosts from inventory..."
    HOSTS=()
    while IFS= read -r line; do
        if [[ $line =~ ansible_host:\ ([0-9.]+) ]]; then
            IP="${BASH_REMATCH[1]}"
        elif [[ $line =~ ansible_user:\ (.+) ]]; then
            USER="${BASH_REMATCH[1]}"
            if [ -n "$IP" ] && [ -n "$USER" ]; then
                HOSTS+=("${USER}@${IP}")
                IP=""
                USER=""
            fi
        fi
    done < inventory/hosts.yml
else
    echo "❌ File inventory/hosts.yml not found!"
    echo "   Run first: ./scripts/setup-inventory.sh"
    exit 1
fi

echo "🔑 Configuring SSH keys for Raspberry Pi machines..."
echo ""

# Check if SSH key exists
if [ ! -f ~/.ssh/id_rsa.pub ] && [ ! -f ~/.ssh/id_ed25519.pub ]; then
    echo "📝 Generating new SSH key..."
    ssh-keygen -t ed25519 -C "ansible-k3s" -f ~/.ssh/id_ed25519 -N ""
    echo "✅ SSH key generated!"
    echo ""
fi

# Determine which key to use
if [ -f ~/.ssh/id_ed25519.pub ]; then
    PUB_KEY=~/.ssh/id_ed25519.pub
elif [ -f ~/.ssh/id_rsa.pub ]; then
    PUB_KEY=~/.ssh/id_rsa.pub
else
    echo "❌ No public SSH key found!"
    exit 1
fi

echo "Using key: $PUB_KEY"
echo ""

# Copy key to each host
for HOST in "${HOSTS[@]}"; do
    echo "📤 Copying key to $HOST..."
    ssh-copy-id -i "$PUB_KEY" "$HOST" || {
        echo "⚠️  Failed to copy key to $HOST"
        echo "   You may need to enter the password manually"
    }
    echo ""
done

echo "✅ SSH key configuration completed!"
echo ""
echo "Now you can run the playbooks without needing to type the password:"
echo "  ansible-playbook playbooks/site.yml"

