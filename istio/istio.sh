#!/bin/bash

# Installation d'Istio et kiali avec Helm Charts

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

# Étape 1 : Ajout des dépôts Helm nécessaires
echo "🔧 Ajout des dépôts Helm..."
helm repo remove istio 2>/dev/null || true
helm repo remove kiali 2>/dev/null || true

helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo add kiali https://kiali.org/helm-charts
helm repo update

for repo in istio kiali; do
  if ! helm repo list | grep -q "$repo"; then
    echo "❌ Erreur : Le dépôt $repo n'a pas été ajouté correctement."
    exit 1
  fi
done
echo "✅ Dépôts Helm ajoutés avec succès."

# Étape 2 : Création du namespace istio-system
echo "📂 Création du namespace 'istio-system'..."
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespace 'istio-system' créé."

# Étape 3 : Installation des CRD Istio
echo "📦 Installation des CRD d'Istio..."
helm upgrade --install istio-base istio/base \
  --namespace istio-system \
  --wait \
  --timeout 5m

if ! kubectl get crd gateways.networking.istio.io &> /dev/null; then
  echo "❌ Erreur : Les CRD d'Istio n'ont pas été installées correctement."
  exit 1
fi
echo "✅ CRD d'Istio installées."

# Étape 4 : Installation du control plane Istio
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

# Étape 5 : Installation de Kiali
echo "🧭 Installation de Kiali..."
helm upgrade --install istio-kiali kiali/kiali-server \
  --namespace istio-system \
  --set auth.strategy="anonymous" \
  --wait \
  --timeout 5m

if ! kubectl get pods -n istio-system -l app.kubernetes.io/name=kiali -o name | grep -q pod; then
  echo "❌ Erreur : Kiali n'a pas été installé correctement."
  kubectl describe pod -n istio-system -l app.kubernetes.io/name=kiali
  exit 1
fi
echo "✅ Kiali installé."

# Étape 6 : Exposition de Kiali
echo "🌐 Configuration de l'accès à Kiali..."

echo "🔄 Patch du service Kiali en NodePort..."
kubectl patch svc kiali -n istio-system -p '{"spec": {"type": "NodePort"}}' || true


# Étape 7 : Configuration de l'injection automatique d'Envoy
echo "🛠️ Configuration de l'injection automatique dans le namespace 'development'..."
kubectl create namespace development --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace development istio-injection=enabled --overwrite

if ! kubectl get namespace development -o jsonpath='{.metadata.labels.istio-injection}' | grep -q "enabled"; then
  echo "❌ Erreur : Le label 'istio-injection=enabled' n'a pas été appliqué correctement."
  exit 1
fi
echo "✅ Injection automatique activée dans 'development'."

# Étape 8 : Vérifications finales
echo "🔍 Vérifications finales..."
kubectl get namespace development --show-labels
kubectl get pods -n istio-system
kubectl get svc -n istio-system
kubectl get namespace -L istio-injection

echo "✅ Installation d'Istio et de Kiali terminée avec succès !"
echo "ℹ️ Accédez à Kiali via : http://kiali.localhost/kiali"