#!/bin/bash

# Stop on error
set -e


# Variables
USER_NAME="awx"  # Remplace "awx" si ton utilisateur a un autre nom
ANSIBLE_CFG_DIR="/home/$USER_NAME/Ansible"
ANSIBLE_LOG="/var/log/ansible/ansible.log"
SSH_KEY_PATH="$HOME/.ssh/ansible"


# === Fonction pour vérifier les erreurs ===
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ Erreur lors de l'étape: $1"
        exit 1
    fi
}


# === Etape 1: Mettre à jour le système ===
echo "🔄 Mise à jour du système..."
sudo dnf update -y
check_error "Mise à jour du système"


# === Etape 2: Installer le dépôt EPEL ===
echo "📦 Installation d'EPEL..."
sudo dnf install -y epel-release
check_error "Installation d'EPEL"


# === Etape 3: Installer Ansible ===
echo "⚙️ Installation d'Ansible..."
sudo dnf install -y ansible
check_error "Installation d'Ansible"


# === Etape 4: Vérifier la version d'Ansible ===
echo "ℹ️ Version d'Ansible installée:"
ansible --version
check_error "Vérification de la version"


# === Etape 5: Créer le répertoire et fichier de log ===
echo "📝 Configuration des logs..."
sudo mkdir -p /var/log/ansible
sudo touch "$ANSIBLE_LOG"
sudo chown "$USER_NAME":"$USER_NAME" "$ANSIBLE_LOG"
sudo chmod 644 "$ANSIBLE_LOG"
check_error "Configuration des logs"


# === Etape 6: Créer le fichier ansible.cfg ===
echo "⚙️ Configuration d'Ansible..."
cat <<EOF > "$ANSIBLE_CFG_DIR/ansible.cfg"
[defaults]
log_path = $ANSIBLE_LOG
gathering = explicit
host_key_checking = False
EOF
check_error "Création du fichier de configuration"


# === Etape 7: Générer une clé SSH pour Ansible ===
echo "🔑 Génération de la clé SSH..."
mkdir -p "$HOME/.ssh" || true
ssh-keygen -t ed25519 -C "ansible" -f "$SSH_KEY_PATH" -N ""
check_error "Génération de la clé SSH"


# === Etape 9: Créer le fichier inventaire ===
echo "📋 Création de l'inventaire..."
cat <<EOF > "$ANSIBLE_CFG_DIR/inventory"
[haproxy_srv]
[haproxy_srv]
haproxy1 ansible_host=192.168.222.93 ansible_user=haproxy1 ansible_ssh_private_key_file=~/.ssh/ansible
haproxy2 ansible_host=192.168.222.94 ansible_user=haproxy2 ansible_ssh_private_key_file=~/.ssh/ansible

[control_plane]
k8s1 ansible_host=192.168.222.97 ansible_user=k8s1 ansible_ssh_private_key_file=~/.ssh/ansible
k8s2 ansible_host=192.168.222.98 ansible_user=k8s2 ansible_ssh_private_key_file=~/.ssh/ansible

[worker_node]
node1 ansible_host=192.168.222.95 ansible_user=node1 ansible_ssh_private_key_file=~/.ssh/ansible
EOF
check_error "Création de l'inventaire"



# === Finalisation ===
echo -e "\n✅ Ansible a été installé et configuré avec succès!"
echo -e "📌 Points importants:"
echo -e "- Configuration: $ANSIBLE_CFG_DIR/ansible.cfg"
echo -e "- Clé SSH générée: $SSH_KEY_PATH"
echo -e "- Inventaire: $ANSIBLE_CFG_DIR/inventory"
echo -e "- Logs: $ANSIBLE_LOG"
