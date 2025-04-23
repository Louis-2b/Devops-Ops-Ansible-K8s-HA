#!/bin/bash

set -e  # Arrêter le script en cas d'erreur


# === Prérequis : installation de sshpass ===
echo "🔧 Vérification de l'installation de sshpass..."
if ! command -v sshpass &> /dev/null; then
  echo "sshpass n'est pas installé. Installation en cours..."
  sudo dnf install -y sshpass || {
    echo "❌ Échec de l'installation de sshpass"
    exit 1
  }
else
  echo "✅ sshpass est déjà installé"
fi


# === Variable ===
PUB_KEY="$HOME/.ssh/ansible.pub"


# Vérification que la clé publique existe
if [ ! -f "$PUB_KEY" ]; then
  echo "❌ La clé publique $PUB_KEY n'existe pas"
  exit 1
fi


# === Mot de passe commun pour tous les hôtes ===
read -s -p "🔐 Entrez le mot de passe SSH pour les serveurs distants : " SSH_PASSWORD
echo # Pour aller à la ligne après la saisie du mot de passe


# === Liste des utilisateurs et IPs ===
declare -A HOSTS=(
  [k8s1]=192.168.222.98
  [k8s2]=192.168.222.97
  [node1]=192.168.222.95
  [haproxy1]=192.168.222.93
  [haproxy2]=192.168.222.94
)

# === Boucle sur chaque hôte ===
for USER in "${!HOSTS[@]}"; do
  HOST="${HOSTS[$USER]}"
  echo "🔑 Copie de la clé vers $USER@$HOST..."
  sshpass -p "$SSH_PASSWORD" ssh-copy-id -i "$PUB_KEY" -o StrictHostKeyChecking=no "$USER@$HOST"
  echo "✅ Clé copiée avec succès vers $USER@$HOST"
  echo "----------------------------------------"
done



echo "✨ Opération terminée pour tous les hôtes"
