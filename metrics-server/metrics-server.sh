#!/bin/bash

# -e : arrête le script en cas d'erreur
# -u : traite les variables non définies comme des erreurs
# -o pipefail : propage les erreurs dans les pipelines
set -euo pipefail


# Définition des variables
YAML_FILE="metrics-server-ha.yaml"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
FLAG="--enable-aggregator-routing=true"
NAMESPACE="kube-system"
METRICS_SERVER_URL=https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability-1.21+.yaml

# Vérification des prérequis
if ! command -v kubectl &> /dev/null; then
  echo "❌ Erreur : kubectl n'est pas installé." >&2
  exit 1
fi

if ! command -v wget &> /dev/null; then
  echo "❌ Erreur : wget n'est pas installé." >&2
  exit 1
fi


# Téléchargement du fichier de déploiement officiel de Metrics Server en version HA
echo "📥 Téléchargement du fichier Metrics Server HA..."
wget -q "$METRICS_SERVER_URL" -O "$YAML_FILE"


# Modification des paramètres du conteneur Metrics Server
echo "🛠️  Modification des arguments du conteneur Metrics Server..."
# Met à jour les arguments
sed -i '/- --secure-port=.*/c\        - --secure-port=4443' "$YAML_FILE"
sed -i '/--metric-resolution=15s/a\        - --kubelet-insecure-tls' "$YAML_FILE"


# Modification du port du conteneur dans la définition du pod
echo "🔁 Changement du port container à 4443..."
sed -i '/containerPort: 10250/c\        - containerPort: 4443' "$YAML_FILE"


# Ajout des tolerations pour permettre l'exécution sur les nœuds control-plane
echo "➕ Ajout des tolerations pour le control-plane..."
awk '
{
  print
  if ($0 ~ /serviceAccountName: metrics-server/) {
    print "      tolerations:"
    print "      - key: \"node-role.kubernetes.io/control-plane\""
    print "        operator: \"Exists\""
    print "        effect: \"NoSchedule\""
  }
}
' "$YAML_FILE" > tmp.yaml && mv tmp.yaml "$YAML_FILE"


# Vérification et configuration de l'API server Kubernetes
echo "🧩 Vérification du paramètre $FLAG dans kube-apiserver..."
if sudo grep -- "$FLAG" "$APISERVER_MANIFEST" > /dev/null; then
  echo "✅ L'option $FLAG est déjà présente dans kube-apiserver.yaml."
else
  echo "🔧 Ajout de $FLAG dans kube-apiserver.yaml..."
  sudo sed -i "/- kube-apiserver/a\    - $FLAG" "$APISERVER_MANIFEST"
  echo "✅ Ajout effectué. Le kubelet redémarrera automatiquement le kube-apiserver."
fi


# Déploiement de Metrics Server dans le cluster
echo "🚀 Déploiement de Metrics Server..."
if ! kubectl apply -f "$YAML_FILE" -n "$NAMESPACE"; then
  echo "❌ Erreur : Échec du déploiement de Metrics Server." >&2
  exit 1
fi


# Attente du déploiement avec une vérification active
echo "⏳ Attente du déploiement de Metrics Server (jusqu'à 3 minutes)..."
timeout 180s kubectl -n "$NAMESPACE" wait --for=condition=ready pod -l k8s-app=metrics-server --timeout=180s || {
  echo "❌ Erreur : Les pods Metrics Server ne sont pas prêts après 3 minutes." >&2
  exit 1
}


# Vérification du déploiement
echo "🔍 Vérification des pods Metrics Server..."
kubectl -n "$NAMESPACE" get pods -l k8s-app=metrics-server

echo "🔍 Vérification des API services..."
kubectl get apiservices -l k8s-app=metrics-server


echo "✅ Installation de Metrics Server HA terminée avec succès."