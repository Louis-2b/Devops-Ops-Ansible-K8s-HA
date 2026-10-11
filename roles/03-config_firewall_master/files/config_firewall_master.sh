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

# Ports Kubernetes
open_port "6443" "tcp" "API Kubernetes"
open_port "2379" "tcp" "etcd client"
open_port "2380" "tcp" "etcd peer"
open_port "10250" "tcp" "Kubelet API"
open_port "10251" "tcp" "kube-scheduler"
open_port "10252" "tcp" "kube-controller-manager"


# === Application des règles ===
echo "🔄 Application des règles de pare-feu..."
sudo firewall-cmd --reload
check_error "Rechargement du pare-feu"


# === Vérification finale ===
echo "🔍 Vérification des règles actives:"
sudo firewall-cmd --list-all
check_error "Liste des règles"


echo -e "\n✅ Configuration du pare-feu terminée avec succès ! 🎉"
echo "Ports ouverts:"
echo "- 6443/tcp (Kubernetes API)"
echo "- 2379-2380/tcp (etcd)"
echo "- 10250-10252/tcp (Kube components)"
echo "- 179/tcp (Calico BGP)"
echo "- 4789/udp (VXLAN)"