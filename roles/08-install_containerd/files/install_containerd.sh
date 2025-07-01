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
    local deps=("dnf" "systemctl" "sed")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            handle_error "$dep n'est pas installé"
        fi
    done
}


# === Vérification initiale ===
check_dependencies


# === Mise à jour du système ===
echo "🔄 Mise à jour du système..."
sudo dnf -y update || handle_error "Échec de la mise à jour du système"


# === Installation des dépendances ===
echo "📦 Installation des dépendances..."
sudo dnf -y install dnf-plugins-core || handle_error "Échec de l'installation des dépendances"


# === Ajout du dépôt Docker ===
echo "➕ Ajout du dépôt Docker..."
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || \
    handle_error "Échec de l'ajout du dépôt Docker"


# === Installation de Containerd ===
echo "📥 Installation de Containerd..."
sudo dnf -y install containerd.io || handle_error "Échec de l'installation de Containerd"


# === Vérification de Containerd ===
echo "🔍 Vérification de Containerd..."
if [[ ! -x /usr/bin/containerd ]]; then
    handle_error "/usr/bin/containerd n'est pas exécutable ou absent"
fi

echo "ℹ️ Version de Containerd:"
/usr/bin/containerd --version || handle_error "Échec de l'exécution de containerd"


# === Activation de Containerd ===
echo "⚙️ Activation de Containerd..."
sudo systemctl daemon-reload || handle_error "Échec du rechargement de systemd"
sudo systemctl enable --now containerd || handle_error "Échec de l'activation de Containerd"


# === Configuration pour Kubernetes ===
echo "🔧 Configuration pour Kubernetes..."
sudo mkdir -p /etc/containerd || handle_error "Échec de la création du répertoire de configuration"

echo "⚙️ Génération de la configuration par défaut..."
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null || \
    handle_error "Échec de la génération de la configuration"

echo "🔄 Activation de SystemdCgroup..."
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || \
    handle_error "Échec de la modification de la configuration"


# === Finalisation ===
echo "🔄 Redémarrage final de Containerd..."
sudo systemctl restart containerd || handle_error "Échec du redémarrage de Containerd"


# === Vérification finale ===
echo -e "\n✅ Installation terminée avec succès ! 🎉"
echo -e "\n📋 Résumé des modifications:"
echo "- Système mis à jour"
echo "- Dépôt Docker ajouté"
echo "- Containerd installé (version: $(containerd --version | cut -d' ' -f3))"
echo "- Configuration Kubernetes appliquée"
echo "- Service Containerd activé et démarré"


# Vérification du statut
echo -e "\n🔍 Statut du service Containerd:"
systemctl status containerd --no-pager -l || true