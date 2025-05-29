#!/bin/bash

# Installation istio avec Helm Charts

set -euo pipefail

# Étape 0 : Vérification des dépendances
echo "🔍 Vérification des outils requis (helm et kubectl)..."

for cmd in helm kubectl; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Erreur : $cmd n'est pas installé. Veuillez l'installer avant de continuer."
    exit 1
  fi
done

echo "✅ Helm et kubectl sont disponibles."


# Etape 1 : Ajoutez les dépôts Helm nécessaires
echo "🔧 Ajout des dépôts Helm..."
helm repo remove istio 2>/dev/null || true
helm repo remove kiali 2>/dev/null || true

helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo add kiali https://kiali.org/helm-charts

helm repo update

# Vérification des dépôts
for repo in istio kiali; do
  if ! helm repo list | grep -q "$repo"; then
    echo "❌ Erreur : Le dépôt $repo n'a pas été ajouté correctement."
    exit 1
  fi
done
echo "✅ Dépôts Helm ajoutés avec succès."


# Etape 2 : Création du namespace istio-system
echo "📂 Création du namespace 'istio-system'..."
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl get namespace istio-system &> /dev/null; then
  echo "❌ Erreur : Le namespace 'istio-system' n'a pas été créé correctement."
  exit 1
fi
echo "✅ Namespace 'istio-system' créé."


# Etape 3 : Installer Custom Resource Definitions (CRD)
echo "📦 Installation des CRD d'Istio..."
helm upgrade --install istio-base istio/base \
  --namespace istio-system \
  --wait \
  --timeout 5m
if ! kubectl get crd gateways.networking.istio.io &> /dev/null; then
  echo "❌ Erreur : Les CRD d'Istio n'ont pas été installés correctement."
  exit 1
fi
echo "✅ CRD d'Istio installées."


# Etape 4 : Installation du control plane Istio (istio/istiod)
echo "🚀 Installation du control plane Istio (istiod)..."
helm upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --set defaultRevision=default \
  --wait \
  --timeout 5m
if ! kubectl get deployment istiod -n istio-system &> /dev/null; then
  echo "❌ Erreur : Le control plane Istio (istiod) n'a pas été installé correctement."
  exit 1
fi
echo "✅ Control plane Istio (istiod) installé."


# Étape 5 : Ajout du dépôt Kiali et installation
echo "🧭 Installation de Kiali..."
helm upgrade --install istio-kiali kiali/kiali-server \
  --namespace istio-system \
  --set auth.strategy="anonymous" \
  --wait \
  --timeout 5m
if ! kubectl get pods -n istio-system -l app.kubernetes.io/name=kiali &> /dev/null; then
  echo "❌ Erreur : Kiali n'a pas été installé correctement."
  kubectl describe pod -n istio-system -l app.kubernetes.io/name=kiali
  exit 1
fi
echo "✅ Kiali installé."


# Etape 6 : Configurer l'injection automatique de proxy Envoy
echo "🛠️ Configuration de l'injection automatique de proxy Envoy dans le namespace 'development'..."
kubectl create namespace development --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace development istio-injection=enabled --overwrite
if ! kubectl get namespace development -o yaml | grep -q "istio-injection: enabled"; then
  echo "❌ Erreur : Le label 'istio-injection=enabled' n'a pas été appliqué correctement au namespace 'development'."
  exit 1
fi
echo "✅ Injection automatique configurée pour le namespace 'development'."


# Étape 7 : Vérification finale
echo "🔍 Vérification du label d'injection dans le namespace 'development'..."
kubectl get namespace development --show-labels
echo "📦 Pods dans istio-system :"
kubectl get pods -n istio-system
echo "📡 Services dans istio-system :"
kubectl get svc -n istio-system


echo "✅ Installation d'Istio et des composants associés terminée avec succès !"