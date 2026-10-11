#!/bin/bash

set -e  # Arrêter le script en cas d'erreur

set -x  # 👈 Ajoute ça pour afficher les commandes exécutées


# === Variables ===
SSH_KEY_NAME="haproxy1"  # Nom de base pour les fichiers de clé
SSH_KEY_PATH="$HOME/.ssh/$SSH_KEY_NAME"
PUB_KEY="$SSH_KEY_PATH.pub"
USER="haproxy2"
HOST="192.168.222.94"
SSH_PASSWORD="admin"  # ⛔ à remplacer par ton mot de passe, ou à demander en lecture sécurisée


# === Fonction pour vérifier les erreurs ===
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ Erreur lors de l'étape: $1"
        exit 1
    fi
}


# === Installer sshpass ===
sudo dnf install -y sshpass
check_error "Installer sshpass"


# === Supprimer l'ancienne clé si elle existe ===
if [ -f "$SSH_KEY_PATH" ] || [ -f "$PUB_KEY" ]; then
    echo "🧹 Clés existantes détectées, suppression..."
    rm -f "$SSH_KEY_PATH" "$PUB_KEY"
fi


# === Générer une clé SSH pour haproxy1  ===
echo "🔑 Génération de la clé SSH..."
ssh-keygen -t ed25519 -C "$SSH_KEY_NAME" -f "$SSH_KEY_PATH" -N ""
check_error "Générer une clé SSH pour haproxy1"


# === Copier la clé publique vers haproxy2 ===
echo "🔑 Copie de la clé vers $USER@$HOST..."
sshpass -p "$SSH_PASSWORD" ssh-copy-id -i "$PUB_KEY" -o StrictHostKeyChecking=no "$USER@$HOST"
check_error "copier la clé publique sur haproxy2 "



echo "✨ Opération terminée pour tous les hôtes"
