#!/bin/bash

# Arrêter le script en cas d'erreur et afficher les commandes exécutées
set -eo pipefail

set -x  # 👈 Ajoute ça pour afficher les commandes exécutées


# === Fonction de gestion des erreurs ===
handle_error() {
    echo "❌ Erreur: $1" >&2
    exit 1
}


# === Fonction pour vérifier les dépendances ===
check_dependencies() {
    local deps=("yum" "systemctl" "rpm")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            handle_error "$dep n'est pas installé"
        fi
    done
}


# === Vérification initiale ===
check_dependencies


# === Ajout du dépôt Kubernetes ===
echo "➕ Ajout du dépôt Kubernetes..."
K8S_REPO_FILE="/etc/yum.repos.d/kubernetes.repo"
K8S_VERSION="v1.31"

sudo tee "$K8S_REPO_FILE" >/dev/null <<EOF || handle_error "Échec de la création du fichier repo"
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF


# Vérification que le fichier repo a été créé
if [ ! -f "$K8S_REPO_FILE" ]; then
    handle_error "Le fichier $K8S_REPO_FILE n'a pas été créé"
fi


# === Installation des outils Kubernetes ===
echo "📥 Installation de kubelet, kubeadm et kubectl..."
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes || \
    handle_error "Échec de l'installation des packages Kubernetes"


# === Vérification de l'installation ===
echo "🔍 Vérification de l'installation..."
K8S_PACKAGES=("kubelet" "kubeadm" "kubectl")
for pkg in "${K8S_PACKAGES[@]}"; do
    if ! rpm -q "$pkg" >/dev/null; then
        handle_error "$pkg n'est pas installé"
    fi
done

if [ ! -f /usr/lib/systemd/system/kubelet.service ]; then
    handle_error "Le fichier de service kubelet.service est manquant"
fi


# === Activation de kubelet ===
echo "⚙️ Activation de kubelet..."
sudo systemctl enable --now kubelet || handle_error "Échec de l'activation de kubelet"


# === Vérification finale ===
echo -e "\n✅ Installation terminée avec succès ! 🎉"
echo -e "\n📋 Résumé des modifications:"
echo "- Dépôt Kubernetes ajouté (version $K8S_VERSION)"
echo "- Packages installés: ${K8S_PACKAGES[*]}"
echo "- Service kubelet activé et démarré"


# Vérification du statut
echo -e "\n🔍 Statut du service kubelet:"
systemctl status kubelet --no-pager -l || true