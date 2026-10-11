#!/bin/bash

# Arrêter le script si une commande échoue
set -e

set -x  # 👈 Ajoute ça pour afficher les commandes exécutées


# === Fonction pour vérifier les erreurs ===
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ Erreur lors de l'étape: $1"
        exit 1
    fi
}


# === Variables ===
USER="haproxy2"
HAPROXY2_IP="192.168.222.94"  # IP de haproxy2
SSH_KEY="/home/haproxy1/.ssh/haproxy1"
SSH_PASSWORD="admin"


# === Créer une clé pour Corosync sur haproxy1...===
echo "🔑 Création de la clé Corosync..."
sudo corosync-keygen
check_error "Créer une clé pour Corosync sur haproxy1"


# === Copier la clé vers haproxy2 ===
echo "📤 Envoi de la clé vers haproxy2..."
sudo sshpass -p "$SSH_PASSWORD" scp -o StrictHostKeyChecking=no -i "$SSH_KEY" /etc/corosync/authkey "$USER@$HAPROXY2_IP:/home/haproxy2"
sudo sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$USER@$HAPROXY2_IP" "echo "$SSH_PASSWORD" | sudo -S mv /home/haproxy2/authkey /etc/corosync/"
check_error "Copier la clé vers haproxy2"


# === Créer le fichier de configuration Corosync sur haproxy1...===
echo "Création du fichier de configuration..."
sudo cp /etc/corosync/corosync.conf.example /etc/corosync/corosync.conf
sudo mv /etc/corosync/corosync.conf /etc/corosync/corosync.back
check_error "Créer le fichier de configuration Corosync sur haproxy1"


# === Créer la configuration Corosync sur haproxy1 ===
echo "📝 Création du fichier de configuration..."
sudo tee /etc/corosync/corosync.conf > /dev/null <<EOF
totem {
  version: 2
  secauth: on
  cluster_name: cluster_ha_k8s
  config_version: 3
  ip_version: ipv4
  interface {
    ringnumber: 0
    bindnetaddr: 192.168.222.0
    mcastport: 5405
    ttl: 1
  }
}

nodelist {
  node {
    name: haproxy1
    ring0_addr: 192.168.222.93
    quorum_votes: 1
    nodeid: 1
  }
  node {
    name: haproxy2
    ring0_addr: 192.168.222.94
    quorum_votes: 1
    nodeid: 2
  }
}

quorum {
  provider: corosync_votequorum
  two_node: 1
}

logging {
  debug: off
  to_syslog: yes
}
EOF
check_error "Créer la configuration Corosync sur haproxy1"


# === Copier la configuration vers haproxy2 ===
echo "📤 Envoi de la configuration vers haproxy2..."
sudo sshpass -p "$SSH_PASSWORD" scp -o StrictHostKeyChecking=no -i "$SSH_KEY" /etc/corosync/corosync.conf "$USER@$HAPROXY2_IP:/home/haproxy2"
sudo sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$USER@$HAPROXY2_IP" "echo "$SSH_PASSWORD" | sudo -S mv /home/haproxy2/corosync.conf /etc/corosync/"
check_error "Copier la configuration vers haproxy2"


# === Activer les services (optionnel) ===
echo "🚀 Activation des services sur haproxy1..."
sudo systemctl enable corosync pacemaker
sudo systemctl start corosync pacemaker

echo "🚀 Activation des services sur haproxy2..."
sudo sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$USER@$HAPROXY2_IP" "echo "$SSH_PASSWORD" | sudo -S systemctl enable corosync pacemaker && echo "$SSH_PASSWORD" | sudo -S systemctl start corosync pacemaker"
check_error "Activer les services (optionnel)"


# === Désactiver deux fonctionnalités inutile pour notre cluster (stonith et no-quorum-policy) ===
echo "🚀 Désactive les fonctionnalités inutiles sur haproxy01..."
sudo pcs property set stonith-enabled=false
sudo pcs property set no-quorum-policy=ignore

echo "🚀 Désactive les fonctionnalités inutiles sur haproxy02..."
sudo sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$USER@$HAPROXY2_IP" "echo "$SSH_PASSWORD" | sudo -S pcs property set stonith-enabled=false && echo "$SSH_PASSWORD" | sudo -S pcs property set no-quorum-policy=ignore"
check_error "Désactiver deux fonctionnalités inutile pour notre cluster (stonith et no-quorum-policy)"


echo "✅ Configuration terminée ! 🎉"