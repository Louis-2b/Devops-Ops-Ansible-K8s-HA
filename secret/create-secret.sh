#!/bin/bash

# Ce script crée un Secret Kubernetes pour accéder au registre Nexus

# Variables par défaut
NEXUSIP="nexus.tubie.devops.ops"
NEXUSPORT3="8083"
SECRET_NAME="nexus-secret"
NAMESPACE="development"

# Charger les informations d'authentification depuis les variables d'environnement
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-adminuser}"

# Vérifier si le secret existe déjà
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
    echo "Le secret '$SECRET_NAME' existe déjà dans le namespace '$NAMESPACE'."
else
    # Créer le secret Docker
    kubectl create secret docker-registry $SECRET_NAME \
      --docker-server=$NEXUSIP:$NEXUSPORT3 \
      --docker-username=$NEXUS_USER \
      --docker-password=$NEXUS_PASS \
      --namespace=$NAMESPACE

    echo "Secret '$SECRET_NAME' créé avec succès dans le namespace '$NAMESPACE'."
fi
