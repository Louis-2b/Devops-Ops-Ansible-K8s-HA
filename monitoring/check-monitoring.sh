#!/bin/bash

# Script pour vérifier l'installation de kube-prometheus-stack et accéder aux services

NAMESPACE="monitoring"


echo "Vérification des pods dans l'espace de noms '$NAMESPACE'..."
kubectl --namespace $NAMESPACE get pods -l "release=prometheus"


echo -e "\nVérification des services dans l'espace de noms '$NAMESPACE'..."
kubectl --namespace $NAMESPACE get svc


echo "Vérification du service LoadBalancer Grafana..."
kubectl get svc -n $NAMESPACE grafana -o wide
echo "L'adresse IP dans la colonne EXTERNAL-IP est attribuée par MetalLB pour le service LoadBalancer."


echo "Vérification de l'Ingress Grafana..."
kubectl get ingress -n $NAMESPACE -o wide


echo "Pour voir les adresses IP attribuées, exécutez :"


echo "kubectl get svc -n $NAMESPACE grafana"


echo "kubectl get ingress -n $NAMESPACE -o wide"


echo -e "\nVérification du nom d'utilisateur Grafana..."
kubectl --namespace $NAMESPACE get secret grafana-admin-credentials -o jsonpath="{.data.admin-user}" | base64 --decode
echo ""


echo -e "\nVérification du mot de passe Grafana..."
kubectl --namespace $NAMESPACE get secret grafana-admin-credentials -o jsonpath="{.data.admin-password}" | base64 --decode
echo ""



echo "✨Installation terminée avec succès !!!!"
