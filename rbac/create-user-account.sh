#!/bin/bash

# Script pour créer un compte utilisateur dans Kubernetes
# Prérequis : openssl et kubectl doivent être installés et configurés

set -e  # Arrêter le script en cas d'erreur


# Vérification des prérequis
if ! command -v openssl &>/dev/null || ! command -v kubectl &>/dev/null; then
    echo "Erreur : openssl et/ou kubectl ne sont pas installés."
    exit 1
fi


# Nom de l'utilisateur et groupe auquel il appartient
USER="bienvenue"
GROUP="infra"


# Étape 1 : Générer une clé privée
echo "Génération de la clé privée pour $USER..."
openssl genpkey -algorithm RSA -out "$GROUP-$USER.key" -pkeyopt rsa_keygen_bits:2048
echo "Clé privée créée: $GROUP-$USER.key"


# Étape 2 : Créer une demande de certificat signé (CSR)
echo "Création de la demande de certificat (CSR)..."
openssl req -new -key "$GROUP-$USER.key" -subj "/CN=$USER" -out "$GROUP-$USER.csr"
echo "Demande de certificat créée: $GROUP-$USER.csr"


# Étape 3 : Encoder le CSR en base64 pour Kubernetes
echo "Encodage du CSR en base64..."
CSR_BASE64=$(cat "$GROUP-$USER.csr" | base64 | tr -d "\n")


# Étape 4 : Créer un fichier YAML pour la ressource CSR
echo "Création du fichier YAML pour la CSR..."
cat <<EOF > "$GROUP-$USER-csr.yaml"
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $GROUP-$USER
spec:
  request: $CSR_BASE64
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 8640000
  usages:
  - client auth
EOF
echo "Fichier YAML créé: $GROUP-$USER-csr.yaml"


# Étape 5 : Appliquer la ressource CSR à Kubernetes
echo "Application de la CSR à Kubernetes..."
kubectl apply -f "$GROUP-$USER-csr.yaml"
echo "CSR appliquée dans Kubernetes"


# Étape 6 : Vérifier la CSR
echo "Vérification de la CSR..."
kubectl get csr "$GROUP-$USER"


# Étape 7 : Approuver la CSR
echo "Approbation de la CSR..."
kubectl certificate approve "$GROUP-$USER"
echo "CSR approuvée"


# --- Attendre un moment pour que le certificat soit généré ---
echo "Attente de la génération du certificat..."
sleep 5


# Étape 8 : Vérifier à nouveau la CSR
echo "Vérification de l'état de la CSR après approbation..."
kubectl get csr "$GROUP-$USER"


# Étape 9 : Récupérer le certificat signé
echo "Récupération du certificat signé..."
CERT_BASE64=$(kubectl get csr "$GROUP-$USER" -o jsonpath='{.status.certificate}')

if [ -z "$CERT_BASE64" ]; then
    echo "Erreur: Le certificat n'a pas été généré. Vérifiez l'état de la CSR."
    kubectl get csr "$GROUP-$USER"
    exit 1
fi


# Étape 10 : Décoder et sauvegarder le certificat
echo "Décodage et sauvegarde du certificat..."
echo "$CERT_BASE64" | base64 --decode > "$GROUP-$USER.crt"
echo "Certificat sauvegardé: $GROUP-$USER.crt"



# Étape 11 : Vérifier que le certificat a été créé
if [ -f "$GROUP-$USER.crt" ]; then
    echo "Certificat $GROUP-$USER.crt créé avec succès !"
else
    echo "Erreur : le certificat n'a pas été créé."
    exit 1
fi


echo "Compte utilisateur $USER créé avec succès !"
echo "Fichiers générés : $GROUP-$USER.key, $GROUP-$USER.csr, $GROUP-$USER-csr.yaml, $GROUP-$USER.crt"
