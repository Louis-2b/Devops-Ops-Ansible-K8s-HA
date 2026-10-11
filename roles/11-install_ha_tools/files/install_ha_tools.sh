#!/bin/bash

# Script pour installer les outils de haute disponibilité (Pacemaker, PCS, Corosync)

# Arrêter le script si une commande échoue
set -e

set -x  # 👈 Ajoute ça pour afficher les commandes exécutées


# === Installer les dépendances ===
echo "📦 Activation du dépôt highavailability..."
sudo dnf config-manager --set-enabled highavailability || {
    echo "❌ Erreur lors de l'activation du dépôt highavailability."
    exit 1
}

echo "📦 Installation des paquets sur haproxy1..."
sudo dnf install -y pacemaker pcs corosync


# === Vérifier que les paquets ont été installés avec succès ===
echo "🔍 Vérification des paquets sur haproxy1..."
if rpm -q pacemaker pcs corosync > /dev/null; then
    echo "✅ Les paquets sont installés avec succès sur haproxy1."
else
    echo "❌ Erreur : l'installation des paquets a échoué sur haproxy1."
    exit 1
fi



echo "✅ Script terminé avec succès. 🎉"