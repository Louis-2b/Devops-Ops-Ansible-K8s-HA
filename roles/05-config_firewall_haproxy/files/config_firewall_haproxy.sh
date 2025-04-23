#!/bin/bash

set -e  # Arrêter le script en cas d'erreur

set -x  # 👈 Ajoute ça pour afficher les commandes exécutées


# === Fonction pour vérifier les erreurs ===
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ Erreur lors de l'étape: $1"
        exit 1
    fi
}


# === Fonction pour ouvrir un port ===
open_port() {
    local port=$1
    local protocol=$2
    local description=$3
    
    echo "🔓 Ouverture du port $port/$protocol ($description)..."
    sudo firewall-cmd --permanent --add-port=$port/$protocol
    check_error "Ouverture du port $port/$protocol"
}


# === Installation et activation de firewalld ===
# echo "🛡️ Installation et activation de firewalld..."
# sudo yum install -y firewalld
# sudo systemctl enable --now firewalld
# check_error "Installation/activation de firewalld"



# === Ouverture des ports nécessaires ===

# === Configuration des règles ===
open_port "6443" "tcp" "Port 6443/tcp (API Kubernetes)"
open_port "5404" "udp" "Port 5404/udp (HA Service)"
open_port "5405" "udp" "Port 5405/udp (HA Service)"


# === Ajout du service high-availability ===
echo "🛡️ Activation du service high-availability..."
sudo firewall-cmd --permanent --add-service=high-availability
check_error "Activation du service high-availability"


# === Application des règles ===
echo "🔄 Application des règles de pare-feu..."
sudo firewall-cmd --reload
check_error "Rechargement du pare-feu"


# === Vérification finale ===
echo "🔍 Vérification des règles actives:"
sudo firewall-cmd --list-all
check_error "Liste des règles"


echo -e "\n✅ Configuration du pare-feu terminée avec succès! 🎉"
echo -e "\n📋 Règles appliquées:"
echo "- Port 6443/tcp (API Kubernetes)"
echo "- Port 5404/udp (HA Service)"
echo "- Port 5405/udp (HA Service)"
echo "- Service high-availability"