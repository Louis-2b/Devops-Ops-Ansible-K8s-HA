#!/bin/bash


# Quitter le script en cas d'erreur
set -e


NAMESPACE="my-micro-service"
SERVICE_ACCOUNT="cicd-sa"


# Étape 1 : Créer le namespace
echo "➡️ Création du namespace '${NAMESPACE}'..."
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"


# Étape 2 : Créer le ServiceAccount
echo "➡️ Création du ServiceAccount '${SERVICE_ACCOUNT}'..."
kubectl get sa "${SERVICE_ACCOUNT}" -n "${NAMESPACE}" >/dev/null 2>&1 || \
kubectl create serviceaccount "${SERVICE_ACCOUNT}" -n "${NAMESPACE}"


# Étape 3 : Créer un Secret lié au ServiceAccount
echo "➡️ Création du Secret lié au ServiceAccount '${SERVICE_ACCOUNT}'..."
cat << EOF > cicd-sa-token.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cicd-sa-token
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SERVICE_ACCOUNT}
type: kubernetes.io/service-account-token
EOF


# Étape 4 : Appliquer le Secret
echo "➡️ Application du fichier 'cicd-sa-token.yaml'..."
kubectl apply -f cicd-sa-token.yaml


# Étape 5 : Vérifier le ServiceAccount
echo "➡️ Vérification du ServiceAccount..."
kubectl describe sa "${SERVICE_ACCOUNT}" -n "${NAMESPACE}"


# Étape 6 : Lister les secrets
echo "➡️ Liste des secrets dans le namespace '${NAMESPACE}'..."
kubectl get secrets -n "${NAMESPACE}"


# Étape 7 : Créer le fichier 'cicd-role.yaml'
echo "➡️ Création du fichier 'cicd-role.yaml'..."
cat << EOF > cicd-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${NAMESPACE}
  name: cicd-role
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "watch", "list", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF


# Étape 8 : Appliquer le Role
echo "➡️ Application du fichier 'cicd-role.yaml'..."
kubectl apply -f cicd-role.yaml


# Étape 9 : Créer le fichier 'cicd-rolebinding.yaml'
echo "➡️ Création du fichier 'cicd-rolebinding.yaml'..."
cat << EOF > cicd-rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cicd-rolebinding
  namespace: ${NAMESPACE}
subjects:
- kind: ServiceAccount
  name: ${SERVICE_ACCOUNT}
  namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: cicd-role
  apiGroup: rbac.authorization.k8s.io
EOF


# Étape 10 : Appliquer le RoleBinding
echo "➡️ Application du fichier 'cicd-rolebinding.yaml'..."
kubectl apply -f cicd-rolebinding.yaml


# Étape 11 : Copier le fichier kubeconfig
echo "➡️ Copie de ~/.kube/config vers ~/cicd-kubeconfig.yaml..."
cp /home/k8s1/.kube/config /home/k8s1/best-security/cicd-kubeconfig.yaml


# Étape 12 : Afficher le secret du token
echo "➡️ Affichage du secret 'cicd-sa-token'..."
kubectl get secret cicd-sa-token -n "${NAMESPACE}" -o yaml


# Étape 13 : Récupération automatique du token lié au ServiceAccount
echo "➡️ Récupération automatique du token lié au ServiceAccount..."
SECRET_NAME="cicd-sa-token"
TOKEN=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.token}' | base64 --decode)
echo "✅ Token récupéré :"
echo "${TOKEN}"


# Étape 14 : Génération d’un kubeconfig minimal
echo "➡️ Génération d’un kubeconfig minimal dans 'cicd-kubeconfig.yaml'..."
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat << EOF > /home/k8s1/best-security/cicd-kubeconfig.yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
    user: ${SERVICE_ACCOUNT}
  name: ${SERVICE_ACCOUNT}@${CLUSTER_NAME}
current-context: ${SERVICE_ACCOUNT}@${CLUSTER_NAME}
users:
- name: ${SERVICE_ACCOUNT}
  user:
    token: ${TOKEN}
EOF


echo "🎉 Script terminé avec succès. Le fichier 'cicd-kubeconfig.yaml' est prêt."
