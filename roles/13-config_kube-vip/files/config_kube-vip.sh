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
HAPROXY2_IP="192.168.222.94"
SSH_KEY="/home/haproxy1/.ssh/haproxy1"
VIP="192.168.222.20"
INTERFACE="ens160"
SSH_PASSWORD="admin"


# === réer la ressource IP virtuelle ===
sudo pcs resource create Virtual_ip ocf:heartbeat:IPaddr2 ip="$VIP" cidr_netmask=24 nic="$INTERFACE" op monitor interval=30s timeout=20s meta failure-timeout=5s
check_error "Créer la ressource IP virtuelle"


# === Créer la ressource haproxy ===
sudo pcs resource create haproxy systemd:haproxy op monitor interval=30s timeout=20s
check_error "Créer la ressource haproxy"


# === Configurer la colocation des ressources ===
sudo pcs constraint colocation add haproxy with Virtual_ip INFINITY
check_error "Configurer la colocation des ressources"


# === Configurer l'ordre de démarrage des ressources ===
sudo pcs constraint order Virtual_ip then haproxy
check_error "Configurer l'ordre de démarrage des ressources"


# === Vérifier la connexion entre les serveurs ===
echo "Vérification de la connexion réseau..."
ping -c 4 haproxy1 || echo "Attention: Problème de connexion à haproxy1"
check_error "Vérifier la connexion entre les serveurs"


# Vérifier la connexion haproxy2
sudo sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$USER@$HAPROXY2_IP" "ping -c 4 haproxy2" || echo "Attention: Problème de connexion entre les nœuds"
check_error "Vérifier la connexion haproxy2"


# === Vérifier l'état du cluster ===
echo "Vérification de l'état du cluster..."
sudo pcs status
check_error "Vérifier l'état du cluster"


echo "✅ Configuration terminée ! 🎉"