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


# === Variables de configuration ===
API_ENDPOINT="192.168.222.20:6443"
APISERVER_ADDRESS="192.168.222.98"
POD_NETWORK_CIDR="10.244.0.0/16"
KUBERNETES_VERSION="1.31.7"


# === Test de connexion à l'API ===
# nc -zv -w 2 192.168.222.20 6443
# check_error "Test de connexion à l'API"


# === Initialisation du cluster ===
echo "🚀 Initialisation du cluster Kubernetes..."
sudo kubeadm init \
    --control-plane-endpoint "$API_ENDPOINT" \
    --upload-certs \
    --apiserver-advertise-address "$APISERVER_ADDRESS" \
    --pod-network-cidr "$POD_NETWORK_CIDR" \
    --kubernetes-version "$KUBERNETES_VERSION" | sudo tee /tmp/kubeadm_init_output.txt
check_error "Initialisation du cluster"


# === Post-installation ===
echo "🔧 Configuration de kubectl pour l'utilisateur $(whoami)..."
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
check_error "Post-installation"


# === Deployer Flannel avec kubectl ===
echo "📦 Déploiement de Flannel (plugin CNI)..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
check_error "Deployer Flannel avec kubectl"



echo "✅ Configuration terminée ! 🎉"
