#!/bin/bash

# Script pour appliquer toutes les ressources Kubernetes pour PostgreSQL et pgAdmin

set -e  # Arrête le script en cas d'erreur

kubectl apply -f postgres-pv.yaml
kubectl apply -f postgres-pvc.yaml
kubectl apply -f postgres-secret.yaml
kubectl apply -f postgres-service.yaml
kubectl apply -f postgres-statefulset.yaml
kubectl apply -f pgadmin-service.yaml
kubectl apply -f pgadmin.yaml

echo "Toutes les ressources ont été appliquées avec succès."
