#!/bin/bash

# Script pour appliquer toutes les ressources Kubernetes pour MongoDB

set -e  # Arrête le script en cas d'erreur

kubectl apply -f mongo-volume.yaml
kubectl apply -f mongo-secret.yaml
kubectl apply -f mongo.yaml
kubectl apply -f mongo-configmap.yaml
kubectl apply -f mongo-express.yaml

echo "Toutes les ressources ont été appliquées avec succès."
