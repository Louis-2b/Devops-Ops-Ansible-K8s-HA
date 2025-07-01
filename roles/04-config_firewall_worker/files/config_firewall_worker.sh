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
echo "🛡️ Installation et activation de firewalld..."
sudo yum install -y firewalld
sudo systemctl enable --now firewalld
check_error "Installation/activation de firewalld"


# === Ouverture des ports nécessaires ===

# Ports Worker
open_port "10250" "tcp" "Kubelet (communication Kubernetes)"
open_port "30000-32767" "tcp" "Services NodePort"


# === Application des règles ===
echo "🔄 Application des règles de pare-feu..."
sudo firewall-cmd --reload
check_error "Rechargement du pare-feu"


# === Vérification finale ===
echo "🔍 Vérification des règles actives:"
sudo firewall-cmd --list-all
check_error "Liste des règles"


echo -e "\n✅ Configuration terminée avec succès ! 🎉"
echo "Ports ouverts :"
echo "- 10250/tcp (Kubelet)"
echo "- 30000-32767/tcp (NodePort)"