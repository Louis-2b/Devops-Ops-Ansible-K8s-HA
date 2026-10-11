#!/bin/bash

# Script pour tester les autorisations de l'utilisateur bienvenue dans Kubernetes

set -e  # Arrêter le script en cas d'erreur


# Définir les variables
USER="bienvenue"



# Étape 1 : Vérifier les autorisations avec auth can-i
echo "Vérification des autorisations de l'utilisateur $USER..."
echo "---------------------------------------------------"

# Ressources et verbes à tester
resources=("pods" "services" "deployments" "statefulsets")
verbs=("get" "list" "create" "delete" "update")

# Boucle sur chaque ressources/verbs
for resource in "${resources[@]}"; do
    echo "Ressource : $resource"
    for verb in "${verbs[@]}"; do
        if kubectl auth can-i "$verb" "$resource" --as "$USER" &>/dev/null; then
            echo "  - Peut $verb $resource : Oui"
        else
            echo "  - Peut $verb $resource : Non"
        fi
    done
    echo ""
done
