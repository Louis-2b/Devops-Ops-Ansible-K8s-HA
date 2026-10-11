#!/bin/bash

# Arrêt en cas d'erreur
set -e

# Script pour installer et configurer MetalLB dans Kubernetes
# Vérifie si kubectl est présent
if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl non trouvé. Veuillez l'installer et configurer l'accès au cluster Kubernetes."
  exit 1
fi


# === ✅ Paramètre : plage IP à utiliser ===
IP_RANGE=${1:-"192.168.222.100-192.168.222.150"}

echo "➡️  Utilisation de la plage IP : $IP_RANGE"


# === Récupérer la dernière version de MetalLB ===
echo "📦 Récupération de la dernière version de MetalLB..."
tubie_metag=$(curl -s https://api.github.com/repos/metallb/metallb/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')

if [[ -z "$tubie_metag" ]]; then
  echo "❌ Impossible de récupérer la version de MetalLB."
  exit 1
fi

echo "✅ Version de MetalLB : $tubie_metag"


# === Créer un dossier pour MetalLB et s'y déplacer ===
echo "Création du dossier ~/metallb et déplacement..."
INSTALL_DIR="/home/k8s1/metallb"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"


# === Télécharger le manifeste MetalLB ===
echo "📥 Téléchargement du manifeste MetalLB..."
wget https://raw.githubusercontent.com/metallb/metallb/v$tubie_metag/config/manifests/metallb-native.yaml


# === Appliquer le manifeste MetalLB ===
echo "🚀 Application du manifeste MetalLB..."
kubectl apply -f metallb-native.yaml


# === Attendre que les pods soient prêts ===
echo "⏳ Attente de la disponibilité des pods MetalLB..."
kubectl -n metallb-system wait --for=condition=ready pod --all --timeout=120s


# === Exporter la configuration des webhooks ===
echo "🛠  Exportation de la configuration des webhooks..."
kubectl -n metallb-system get validatingwebhookconfiguration -o yaml > patch-webhook-metallb.yaml


# === Modifier failurePolicy de Fail à Ignore ===
echo "✏️  Modification du failurePolicy dans patch-webhook-metallb.yaml..."
sed -i '/path: \/validate-metallb-io-v1beta1-ipaddresspool/,/failurePolicy:/s/failurePolicy: Fail/failurePolicy: Ignore/' patch-webhook-metallb.yaml
sed -i '/path: \/validate-metallb-io-v1beta1-l2advertisement/,/failurePolicy:/s/failurePolicy: Fail/failurePolicy: Ignore/' patch-webhook-metallb.yaml


# === Appliquer le patch ===
echo "📄 Application du patch du webhook..."
kubectl apply -f patch-webhook-metallb.yaml


# === Créer le fichier ippools.yaml ===
echo "📘 Création du fichier ippools.yaml..."
cat << EOF > /home/k8s1/metallb/ippools.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  namespace: metallb-system
  name: production
spec:
  addresses:
  - $IP_RANGE
EOF


# === Appliquer le fichier ippools.yaml ===
echo "🧭 Application du fichier ippools.yaml..."
kubectl apply -f ippools.yaml


# === Créer le fichier l2adv.yaml ===
echo "📘 Création du fichier l2adv.yaml..."
cat << EOF > /home/k8s1/metallb/l2adv.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: arpsetup
  namespace: metallb-system
spec:
  ipAddressPools:
  - production
EOF


# === Appliquer le fichier l2adv.yaml ===
echo "📄 Application du fichier l2adv.yaml..."
kubectl apply -f l2adv.yaml


# === Vérification finale ===
echo "🔍 Vérification de l'installation de MetalLB..."
kubectl -n metallb-system get pods
kubectl -n metallb-system get ipaddresspool
kubectl -n metallb-system get l2advertisement

echo "✅ Installation et configuration de MetalLB terminées avec succès !"
