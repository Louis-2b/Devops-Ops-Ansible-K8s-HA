#!/bin/bash

# Script pour supprimer toutes les ressources Kubernetes pour MongoDB

set -e  # Arrête le script en cas d'erreur

kubectl delete -f mongo.yaml
kubectl delete -f mongo-express.yaml
kubectl delete -f mongo-configmap.yaml
kubectl delete -f mongo-volume.yaml
kubectl delete -f mongo-secret.yaml

echo "Toutes les ressources ont été supprimées avec succès."
