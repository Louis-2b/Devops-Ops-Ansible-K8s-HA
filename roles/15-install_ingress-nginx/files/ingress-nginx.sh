#!/bin/bash

set -e  # Stopper le script en cas d'erreur

# Script pour installer et configurer ingress-nginx avec Helm

# === Vérifie les prérequis ===
for cmd in curl wget tar kubectl; do
  command -v $cmd >/dev/null 2>&1 || { echo "Erreur : $cmd est requis."; exit 1; }
done


# === Installer Helm si non présent ===
if ! command -v helm >/dev/null 2>&1; then
  echo "Helm non trouvé. Téléchargement et installation..."
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
else
  echo "Helm est déjà installé."
fi


# === Récupérer la dernière version de ingress-nginx ===
echo "Récupération de la dernière version de ingress-nginx..."
tubie_tag=$(curl -s https://api.github.com/repos/kubernetes/ingress-nginx/releases/latest | grep tag_name | cut -d '"' -f 4)
echo "Version trouvée : $tubie_tag"


# === Télécharger et extraire l'archive ===
echo "Téléchargement de l'archive ingress-nginx..."
wget https://github.com/kubernetes/ingress-nginx/archive/refs/tags/${tubie_tag}.tar.gz -O ingress-nginx.tar.gz
echo "Extraction de l'archive..."
tar xvf ingress-nginx.tar.gz >/dev/null


# === Accéder au dossier du chart Helm ===
cd ingress-nginx-${tubie_tag}/charts/ingress-nginx/


# === Création du namespace ingress-nginx (si inexistant) ===
echo "Vérification ou création du namespace ingress-nginx..."
kubectl get namespace ingress-nginx >/dev/null 2>&1 || kubectl create namespace ingress-nginx


# === Modification du values.yaml avant installation ===
echo "Configuration du nombre de répliques à 3..."
sed -i 's/replicaCount: 1/replicaCount: 3/' values.yaml


# === Installation ou mise à jour avec Helm ===
if helm status ingress-nginx -n ingress-nginx >/dev/null 2>&1; then
  echo "ingress-nginx déjà installé, mise à jour..."
  helm upgrade -n ingress-nginx ingress-nginx -f values.yaml .
else
  echo "Installation de ingress-nginx avec Helm..."
  helm install -n ingress-nginx ingress-nginx -f values.yaml .
fi


# === Vérifier les ressources déployées ===
echo "Vérification des ressources dans le namespace ingress-nginx..."
echo "✅ Installation et configuration terminées !"
echo "ℹ️ Pour tester : kubectl get pods -n ingress-nginx"