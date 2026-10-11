#!/bin/bash

# Arrêter le script en cas d'erreur et afficher les commandes
set -eo pipefail

set -x  # 👈 Ajoute ça pour afficher les commandes exécutées


# === Fonction pour gérer les erreurs ===
handle_error() {
    echo "❌ Erreur: $1" >&2
    exit 1
}


# === Variables ===
declare -A HOST_ENTRIES=(
    ["192.168.222.20"]="kube-vip"
    ["192.168.222.98"]="k8s1"
    ["192.168.222.97"]="k8s2"
    ["192.168.222.95"]="node1"
    ["192.168.222.93"]="haproxy1"
    ["192.168.222.94"]="haproxy2"
)


PACKAGES=(
    vim tree net-tools telnet git python3-pip 
    sshpass nc
)


# === Configuration des entrées d'hôte ===
echo "🌐 Configuration des entrées /etc/hosts..."
for ip in "${!HOST_ENTRIES[@]}"; do
    echo "$ip ${HOST_ENTRIES[$ip]}" | sudo tee -a /etc/hosts >/dev/null || 
    handle_error "Échec de l'ajout de $ip à /etc/hosts"
done


# === Mise à jour du système ===
echo "🔄 Mise à jour du système..."
sudo dnf update -y || handle_error "Échec de la mise à jour du système"


# === Installation des dépôts et paquets ===
echo "📦 Installation des paquets..."
sudo dnf install -y epel-release || handle_error "Échec de l'installation d'EPEL"
sudo dnf install -y "${PACKAGES[@]}" || handle_error "Échec de l'installation des paquets"


# === Configuration SELinux ===
echo "🛡️ Configuration SELinux pour HAProxy..."
sudo setsebool -P haproxy_connect_any=1 || handle_error "Échec de la configuration SELinux"


# === Configuration Vim ===
echo "✏️ Configuration de Vim pour YAML..."
VIMRC="$HOME/.vimrc"
cat <<EOF > "$VIMRC" || handle_error "Échec de la configuration Vim"
autocmd FileType yaml setlocal ai ts=2 sw=2 et
syntax on
filetype plugin indent on
EOF


# === Configuration SSH ===
echo "🔒 Modification de la configuration SSH..."
sudo sed -i \
    -e 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' \
    -e 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' \
    /etc/ssh/sshd_config || handle_error "Échec de la modification sshd_config"

sudo systemctl restart sshd || handle_error "Échec du redémarrage du service SSH"


# === Configuration du temps ===
echo "⏰ Configuration du temps système..."
sudo timedatectl set-local-rtc 0 || handle_error "Échec de la configuration RTC"
sudo timedatectl set-ntp true || handle_error "Échec de l'activation NTP"
sudo systemctl restart chronyd || handle_error "Échec du redémarrage de chronyd"


# === Vérification finale ===
echo -e "\n✅ Toutes les configurations ont été appliquées avec succès !"
echo -e "\n📋 Résumé des modifications :"
echo "- Entrées /etc/hosts ajoutées"
echo "- Système mis à jour"
echo "- Paquets installés: ${PACKAGES[*]}"
echo "- SELinux configuré pour HAProxy"
echo "- Vim configuré pour YAML"
echo "- SSH configuré avec authentification par mot de passe"
echo "- Synchronisation du temps activée"