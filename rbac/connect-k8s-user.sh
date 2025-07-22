#!/bin/bash

# Script pour configurer et se connecter au cluster Kubernetes

set -e  # Arrête le script en cas d'erreur


# Vérification des prérequis
if ! command -v kubectl &>/dev/null; then
    echo "Erreur : kubectl n'est pas installé."
    exit 1
fi


# Définir le nom de l'utilisateur et groupe auquel il appartient
USER="bienvenue"
GROUP="infra"


# Étape 1 : Vérification que nous sommes sur le nœud master
if ! kubectl cluster-info &>/dev/null; then
    echo "Erreur: Impossible de se connecter au cluster Kubernetes"
    exit 1
fi


# Étape 2 : Récupération des informations du cluster
echo "Récupération des informations du cluster..."
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "API Server: $API_SERVER"


# Étape 3 : Vérification des fichiers de certificats
echo "Vérification des fichiers de certificats..."
for file in "$GROUP-$USER.crt" "$GROUP-$USER.key"; do
    if [ ! -f "$file" ]; then
        echo "Erreur : Le fichier $file n'existe pas."
        exit 1
    fi
done


# Étape 4 : Création du fichier kubeconfig
echo "Création du fichier kubeconfig..."
KUBECONFIG_FILE="$GROUP-$USER.conf"

# --- Copie du fichier de configuration existant comme base ---
cp /home/master/.kube/config "$KUBECONFIG_FILE"

# --- Encodage des certificats en base64 ---
echo "Encodage des certificats..."
CERT_DATA=$(base64 "$GROUP-$USER.crt" | tr -d "\n")
KEY_DATA=$(base64 "$GROUP-$USER.key" | tr -d "\n")

# Récupération du CA data du cluster
CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Création du fichier kubeconfig personnalisé
cat <<EOF > "$KUBECONFIG_FILE"
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $CA_DATA
    server: $API_SERVER
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: $GROUP-$USER
  name: $GROUP-$USER@kubernetes
current-context: $GROUP-$USER@kubernetes
kind: Config
preferences: {}
users:
- name: $GROUP-$USER
  user:
    client-certificate-data: $CERT_DATA
    client-key-data: $KEY_DATA
EOF
echo "Fichier kubeconfig créé: $KUBECONFIG_FILE"
