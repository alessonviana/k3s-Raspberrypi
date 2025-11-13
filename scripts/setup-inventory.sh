#!/bin/bash
# Interactive script to configure Ansible inventory

set -e

INVENTORY_FILE="inventory/hosts.yml"
PASSWORDS_FILE="inventory/.passwords.yml"
GROUP_VARS_ALL="group_vars/all.yml"

echo "🚀 k3s Inventory Configuration"
echo "=================================="
echo ""
echo "⚠️  IMPORTANT: The generated inventory/hosts.yml file contains"
echo "   sensitive information \(IPs, users\) and WILL NOT be committed to GitHub\."
echo "   An example file \(hosts\.yml\.example\) is available\."
echo ""

# Create directories if they do not exist
mkdir -p inventory group_vars

# Function to validate IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Collect number of masters and workers
echo "📋 Initial Configuration"
echo "----------------------"
read -p "How many masters do you want to configure\? [1]: " NUM_MASTERS
NUM_MASTERS=${NUM_MASTERS:-1}

read -p "How many workers do you want to configure\? [2]: " NUM_WORKERS
NUM_WORKERS=${NUM_WORKERS:-2}

echo ""

# Collect master information
echo "📋 Masters Configuration \(main nodes\)"
echo "---------------------------------------------"

MASTERS=()
DEFAULT_USER=""
FIRST_MASTER_IP=""

for i in $(seq 1 $NUM_MASTERS); do
    echo ""
    echo "Master #$i:"
    read -p "  Master name [master$(printf "%02d" $i)]: " MASTER_NAME
    MASTER_NAME=${MASTER_NAME:-master$(printf "%02d" $i)}
    
    while true; do
        read -p "  Master IP: " MASTER_IP
        if validate_ip "$MASTER_IP"; then
            break
        else
            echo "  ❌ Invalid IP\. Please try again\."
        fi
    done
    
    if [ -z "$DEFAULT_USER" ]; then
        read -p "  SSH user [pi]: " MASTER_USER
        MASTER_USER=${MASTER_USER:-pi}
        DEFAULT_USER=$MASTER_USER
    else
        read -p "  SSH user [${DEFAULT_USER}]: " MASTER_USER
        MASTER_USER=${MASTER_USER:-$DEFAULT_USER}
    fi
    
    read -sp "  SSH password: " MASTER_PASSWORD
    echo ""
    
    read -p "  SSH port [22]: " MASTER_PORT
    MASTER_PORT=${MASTER_PORT:-22}
    
    MASTERS+=("$MASTER_NAME|$MASTER_IP|$MASTER_USER|$MASTER_PORT|$MASTER_PASSWORD")
    
    # The first master will be used as reference for the cluster
    if [ $i -eq 1 ]; then
        FIRST_MASTER_IP="$MASTER_IP"
    fi
done

# Ensure FIRST_MASTER_IP is defined (extract from first master if necessary)
if [ -z "$FIRST_MASTER_IP" ] && [ ${#MASTERS[@]} -gt 0 ]; then
    IFS='|' read -r name ip user port password <<< "${MASTERS[0]}"
    FIRST_MASTER_IP="$ip"
fi

echo ""

# Collect worker information
echo "📋 Workers Configuration \(worker nodes\)"
echo "-----------------------------------------------"

WORKERS=()
for i in $(seq 1 $NUM_WORKERS); do
    echo ""
    echo "Worker #$i:"
    read -p "  Worker name [worker$(printf "%02d" $i)]: " WORKER_NAME
    WORKER_NAME=${WORKER_NAME:-worker$(printf "%02d" $i)}
    
    while true; do
        read -p "  Worker IP: " WORKER_IP
        if validate_ip "$WORKER_IP"; then
            break
        else
            echo "  ❌ Invalid IP\. Please try again\."
        fi
    done
    
    read -p "  SSH user [pi]: " WORKER_USER
    WORKER_USER=${WORKER_USER:-pi}
    
    read -sp "  SSH password: " WORKER_PASSWORD
    echo ""
    
    read -p "  SSH port [22]: " WORKER_PORT
    WORKER_PORT=${WORKER_PORT:-22}
    
    WORKERS+=("$WORKER_NAME|$WORKER_IP|$WORKER_USER|$WORKER_PORT|$WORKER_PASSWORD")
done

echo ""

# Collect general information
echo "📋 General Settings"
echo "----------------------"
read -p "Timezone [America/Toronto]: " TIMEZONE
TIMEZONE=${TIMEZONE:-America/Toronto}

read -p "k3s version \[leave empty for latest stable\]: " K3S_VERSION
K3S_VERSION=${K3S_VERSION:-""}

read -p "Flannel backend [vxlan]: " FLANNEL_BACKEND
FLANNEL_BACKEND=${FLANNEL_BACKEND:-vxlan}

echo ""
echo "📝 Configuration summary:"
echo "=========================="
echo "Masters ($NUM_MASTERS):"
for master_info in "${MASTERS[@]}"; do
    IFS='|' read -r name ip user port password <<< "$master_info"
    echo "  - $name ($ip:$port) - user: $user"
done
echo ""
echo "Workers ($NUM_WORKERS):"
for worker_info in "${WORKERS[@]}"; do
    IFS='|' read -r name ip user port password <<< "$worker_info"
    echo "  - $name ($ip:$port) - user: $user"
done
echo ""
echo "Settings:"
echo "  Timezone: $TIMEZONE"
echo "  k3s Version: $K3S_VERSION"
echo "  Flannel Backend: $FLANNEL_BACKEND"
echo "  Master IP (para kubeconfig): $FIRST_MASTER_IP"
echo ""

read -p "Confirm and generate files\? (s/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Ss]$ ]]; then
    echo "❌ Operation cancelled\."
    exit 1
fi

echo ""
echo "💡 If you need to edit any of these settings, access the file:"
echo "   $INVENTORY_FILE"
echo ""

# Generate inventory
echo ""
echo "📝 Generating inventory\.\.\."
cat > "$INVENTORY_FILE" <<EOF
---
all:
  children:
    k3s_cluster:
      children:
        k3s_master:
          hosts:
EOF

for master_info in "${MASTERS[@]}"; do
    IFS='|' read -r name ip user port password <<< "$master_info"
    cat >> "$INVENTORY_FILE" <<EOF
            ${name}:
              ansible_host: ${ip}
              ansible_user: ${user}
              ansible_password: ${password}
EOF
    if [ "$port" != "22" ]; then
        cat >> "$INVENTORY_FILE" <<EOF
              ansible_port: ${port}
EOF
    fi
done

cat >> "$INVENTORY_FILE" <<EOF
        k3s_workers:
          hosts:
EOF

for worker_info in "${WORKERS[@]}"; do
    IFS='|' read -r name ip user port password <<< "$worker_info"
    cat >> "$INVENTORY_FILE" <<EOF
            ${name}:
              ansible_host: ${ip}
              ansible_user: ${user}
              ansible_password: ${password}
EOF
    if [ "$port" != "22" ]; then
        cat >> "$INVENTORY_FILE" <<EOF
              ansible_port: ${port}
EOF
    fi
done

# Gerar arquivo de senhas
echo "📝 Gerando arquivo de senhas..."
cat > "$PASSWORDS_FILE" <<EOF
---
# SSH passwords file \(DO NOT COMMIT - it is in \.gitignore\)
# This file contains machine passwords for use with ansible-playbook

EOF

for master_info in "${MASTERS[@]}"; do
    IFS='|' read -r name ip user port password <<< "$master_info"
    cat >> "$PASSWORDS_FILE" <<EOF
${name}_password: ${password}
EOF
done

for worker_info in "${WORKERS[@]}"; do
    IFS='|' read -r name ip user port password <<< "$worker_info"
    cat >> "$PASSWORDS_FILE" <<EOF
${name}_password: ${password}
EOF
done

# Gerar group_vars/all.yml
echo "📝 Generating global variables\.\.\."
cat > "$GROUP_VARS_ALL" <<EOF
---
# Global variables for all machines
ansible_python_interpreter: /usr/bin/python3
ansible_ssh_common_args: '-o StrictHostKeyChecking=no'

# Timezone
timezone: "${TIMEZONE}"

# Default user
default_user: ${DEFAULT_USER}
EOF

# Gerar group_vars/k3s_cluster.yml
echo "📝 Generating cluster variables\.\.\."

# Validar que FIRST_MASTER_IP foi definido
if [ -z "$FIRST_MASTER_IP" ]; then
    echo "❌ Error: First master IP was not defined\!"
    exit 1
fi

cat > "group_vars/k3s_cluster.yml" <<EOF
---
# k3s cluster settings
k3s_version: "${K3S_VERSION}"
k3s_install_dir: /usr/local/bin

# Token to join workers to the cluster \(will be automatically generated by master\)
k3s_token: ""

# Master settings \(using the first master as reference\)
k3s_master_ip: "${FIRST_MASTER_IP}"
k3s_master_url: "https://${FIRST_MASTER_IP}:6443"

# Network settings
k3s_flannel_backend: "${FLANNEL_BACKEND}"

# Additional k3s settings
k3s_extra_args: ""
EOF

echo ""
echo "✅ Configuration completed successfully\!"
echo ""
echo "📁 Generated files:"
echo "  - $INVENTORY_FILE (⚠️  contains sensitive information - will not be committed\)"
echo "  - $PASSWORDS_FILE (⚠️  contains passwords - will not be committed\)"
echo "  - $GROUP_VARS_ALL"
echo "  - group_vars/k3s_cluster.yml"
echo ""
echo "🔒 Security:"
echo "  - The files inventory/hosts\.yml and inventory/\.passwords\.yml are in \.gitignore"
echo "  - These files contain IPs, users and passwords - keep them secure"
echo "  - Never commit these files to GitHub"
echo ""
echo "🚀 Next steps:"
echo "  1. Test connectivity: ansible all -m ping --ask-pass"
echo "  2. Run deployment: ansible-playbook playbooks/site.yml --ask-pass --ask-become-pass"
echo ""
echo "💡 Tip: You can use the passwords file with:"
echo "   ansible-playbook playbooks/site.yml -e @$PASSWORDS_FILE --ask-pass --ask-become-pass"
echo ""
