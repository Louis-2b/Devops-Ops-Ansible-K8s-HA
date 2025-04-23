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
    local deps=("modprobe" "sed" "sysctl" "dnf")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            handle_error "$dep n'est pas installé"
        fi
    done
}


# === Vérification des dépendances ===
check_dependencies


# === Désactivation du swap ===
echo "🔄 Arrêt du swap..."
sudo swapoff -a || handle_error "Échec de la désactivation du swap"

echo "📝 Commentaire de la ligne swap dans /etc/fstab..."
sudo sed -i.bak '/ swap / s/^/#/' /etc/fstab || handle_error "Échec de la modification de /etc/fstab"

echo "🔍 Vérification du swap:"
free -h | grep Swap || echo "⚠️ Impossible de vérifier l'état du swap"


# === Configuration de SELinux ===
echo "🛡️ Mise en mode permissif de SELinux..."
sudo setenforce 0 || handle_error "Échec du passage en mode permissif"

echo "📝 Modification permanente de SELinux..."
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config || \
    handle_error "Échec de la modification de la configuration SELinux"


# === Configuration des modules noyau ===
echo "📦 Configuration des modules pour Kubernetes..."
sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<EOF || handle_error "Échec de la création de k8s.conf"
overlay
br_netfilter
EOF

echo "⚙️ Chargement des modules..."
sudo modprobe overlay || handle_error "Échec du chargement du module overlay"
sudo modprobe br_netfilter || handle_error "Échec du chargement du module br_netfilter"


# === Paramètres réseau ===
echo "🌐 Configuration des paramètres réseau..."
sudo tee /etc/sysctl.d/k8s.conf >/dev/null <<EOF || handle_error "Échec de la création de sysctl.conf"
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

echo "🔄 Application des paramètres sysctl..."
sudo sysctl --system >/dev/null || handle_error "Échec de l'application des paramètres sysctl"


# === Configuration IPVS ===
echo "📡 Configuration IPVS..."
sudo mkdir -p /etc/sysconfig/modules/ || handle_error "Échec de la création du répertoire"

sudo tee /etc/sysconfig/modules/ipvs.modules >/dev/null <<EOF || handle_error "Échec de la création ipvs.modules"
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
EOF

sudo chmod 755 /etc/sysconfig/modules/ipvs.modules || handle_error "Échec du chmod"
sudo bash /etc/sysconfig/modules/ipvs.modules || handle_error "Échec du chargement des modules IPVS"

echo "🔍 Vérification des modules IPVS:"
if ! lsmod | grep -e ip_vs -e nf_conntrack_ipv4; then
    echo "⚠️ Les modules IPVS ne semblent pas chargés"
fi


# === Installation des outils ===
echo "📦 Installation de ipset et ipvsadm..."
sudo dnf install -y ipset ipvsadm >/dev/null || handle_error "Échec de l'installation des paquets"


# === Vérification finale ===
echo -e "\n✅ Configuration terminée avec succès ! 🎉"
echo -e "\n📋 Résumé des modifications:"
echo "- Swap désactivé"
echo "- SELinux en mode permissif"
echo "- Modules noyau chargés (overlay, br_netfilter)"
echo "- Paramètres réseau configurés"
echo "- IPVS configuré"
echo "- Outils ipset et ipvsadm installés"