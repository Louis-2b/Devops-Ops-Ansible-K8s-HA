#!/bin/bash

# Script simple pour désinstaller kube-prometheus-stack (Prometheus et Grafana)

# Arrêter le script si une erreur se produit
set -e

# Nom de l'espace où Prometheus est installé
NAMESPACE="monitoring"


# Étape 1 : Vérifier si kubectl fonctionne
echo "Vérification du cluster Kubernetes..."
if ! kubectl get nodes; then
    echo "Problème : Impossible de se connecter au cluster Kubernetes."
    exit 1
fi


# Étape 2 : Vérifier si Helm est installé
echo "Vérification de Helm..."
if ! helm version; then
    echo "Problème : Helm n'est pas installé."
    exit 1
fi


# Étape 3 : Désinstaller Prometheus si installé
echo "Désinstallation de Prometheus dans '$NAMESPACE'..."
if helm list -n "$NAMESPACE" | grep prometheus; then
    helm uninstall -n "$NAMESPACE" prometheus
    echo "Prometheus désinstallé."
else
    echo "Prometheus n'est pas installé dans '$NAMESPACE'."
fi


# Étape 4 : Supprimer l'espace de noms si il existe
echo "Suppression de l'espace de noms '$NAMESPACE'..."
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl delete namespace "$NAMESPACE"
    echo "Espace de noms '$NAMESPACE' supprimé."
else
    echo "L'espace de noms '$NAMESPACE' n'existe pas."
fi


# Étape 5 : Supprimer le fichier values.yaml si il existe
echo "Vérification du fichier values.yaml..."
if [ -f "values.yaml" ]; then
    sudo rm -rf values.yaml
    echo "Fichier values.yaml supprimé."
else
    echo "Le fichier values.yaml n'existe pas."
fi



echo "Désinstallation terminée !"
