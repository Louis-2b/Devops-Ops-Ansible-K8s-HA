#!/bin/bash

# Script pour vérifier toutes les autorisations du compte de service gitlab dans Kubernetes
# Prérequis : kubectl doit être installé et configuré avec un accès administrateur

set -e  # Arrêter le script en cas d'erreur


# Définir les variables
SA_NAME="system:serviceaccount:default:gitlab"  # Nom complet du compte de service
NAMESPACES=("default" "kube-system")  # Namespaces à vérifier
RESOURCES=("pods" "services" "deployments" "statefulsets" "configmaps" "secrets")  # Ressources courantes à vérifier
VERBS=("get" "list" "create" "update" "delete" "watch")  # Actions courantes à vérifier


# Étape 1 : Vérifier les autorisations pour des ressources et actions spécifiques
echo "Vérification des autorisations spécifiques pour le compte de service $SA_NAME..."
echo "---------------------------------------------------"

for namespace in "${NAMESPACES[@]}"; do
    echo "Namespace : $namespace"
    for resource in "${RESOURCES[@]}"; do
        echo "  Ressource : $resource"
        for verb in "${VERBS[@]}"; do
            if kubectl auth can-i "$verb" "$resource" --as="$SA_NAME" -n "$namespace" &>/dev/null; then
                echo "    - Peut $verb $resource : Oui"
            else
                echo "    - Peut $verb $resource : Non"
            fi
        done
        echo ""
    done
done


echo "Vérification des autorisations terminée pour le compte de service $SA_NAME !"
