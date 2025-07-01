#!/bin/bash

# Script pour supprimer toutes les ressources Kubernetes pour PostgreSQL et pgAdmin

set -e  # Arrête le script en cas d'erreur

kubectl delete -f pgadmin.yaml
kubectl delete -f pgadmin-service.yaml
kubectl delete -f postgres-statefulset.yaml
kubectl delete -f postgres-service.yaml
kubectl delete -f postgres-secret.yaml
kubectl delete -f postgres-pvc.yaml
kubectl delete -f postgres-pv.yaml

echo "Toutes les ressources ont été supprimées avec succès."
