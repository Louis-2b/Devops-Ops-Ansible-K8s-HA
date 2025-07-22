#!/bin/bash

# Script pour créer un compte de service GitLab, son token, son kubeconfig,
# et accorder des autorisations via un Role et un RoleBinding dans Kubernetes
# Prérequis : kubectl doit être installé et configuré avec un accès administrateur

set -e  # Arrêter le script en cas d'erreur


# Définir les variables
SA_NAME="gitlab"
NAMESPACE="default" 
API_SERVER="https://192.168.222.107:6443"


# Étape 1 : Créer le fichier ServiceAccount (gitlab-sa.yaml)
echo "Création du fichier ServiceAccount (gitlab-sa.yaml)..."
cat <<EOF > gitlab-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA_NAME
  namespace: $NAMESPACE
EOF
echo "Fichier gitlab-sa.yaml créé avec succès."

# Appliquer le ServiceAccount
echo "Application du ServiceAccount..."
kubectl apply -f gitlab-sa.yaml

echo "ServiceAccount $SA_NAME appliqué."
kubectl describe serviceaccount $SA_NAME -n $NAMESPACE



# Étape 2 : Créer le fichier Secret pour le jeton (gitlab-sa-token.yaml)
echo "Création du fichier Secret pour le jeton (gitlab-sa-token.yaml)..."
cat <<EOF > gitlab-sa-token.yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-token
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/service-account.name: $SA_NAME
type: kubernetes.io/service-account-token
EOF
echo "Fichier gitlab-sa-token.yaml créé avec succès."

# Appliquer le Secret
echo "Application du Secret pour le jeton..."
kubectl apply -f gitlab-sa-token.yaml

echo "Secret gitlab-token appliqué."
kubectl describe secret gitlab-token -n $NAMESPACE



# Étape 3 : Récupérer le token du Secret
echo "Récupération du token du ServiceAccount..."
TOKEN=$(kubectl get secret gitlab-token -n $NAMESPACE -o jsonpath='{.data.token}' | base64 --decode)
if [ -z "$TOKEN" ]; then
    echo "Erreur : Impossible de récupérer le token du Secret gitlab-token."
    exit 1
fi
echo "token récupéré avec succès."


# Étape 4 : Récupérer le certificat CA du cluster
echo "Récupération du certificat CA du cluster..."
CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
if [ -z "$CA_DATA" ]; then
    echo "Erreur : Impossible de récupérer le certificat CA du cluster."
    exit 1
fi
echo "Certificat CA récupéré."


# Étape 5 : Créer le fichier kubeconfig pour le ServiceAccount (gitlab.conf)
echo "Création du fichier kubeconfig (gitlab.conf)..."
cat <<EOF > gitlab.conf
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $CA_DATA
    server: $API_SERVER
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: $SA_NAME
  name: $SA_NAME@kubernetes
current-context: $SA_NAME@kubernetes
kind: Config
preferences: {}
users:
- name: $SA_NAME
  user:
    token: $TOKEN
EOF
echo "Fichier gitlab.conf créé avec succès."


# Étape 6 : Créer le fichier Role (gitlab-cicd-role.yaml)
echo "Création du fichier Role (gitlab-cicd-role.yaml)..."
cat <<EOF > gitlab-cicd-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: gitlab-cicd-role
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["create", "update", "list"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["create", "update", "list"]
EOF
echo "Fichier gitlab-cicd-role.yaml créé avec succès."

# Appliquer le Role
echo "Application du Role..."
kubectl apply -f gitlab-cicd-role.yaml

echo "Role gitlab-cicd-role appliqué."
kubectl describe role gitlab-cicd-role -n $NAMESPACE


# Étape 7 : Créer le fichier RoleBinding (gitlab-cicd-rolebinding.yaml)
echo "Création du fichier RoleBinding (gitlab-cicd-rolebinding.yaml)..."
cat <<EOF > gitlab-cicd-rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: gitlab-cicd-rolebinding
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: gitlab-cicd-role
subjects:
- kind: ServiceAccount
  name: $SA_NAME
  namespace: $NAMESPACE
EOF
echo "Fichier gitlab-cicd-rolebinding.yaml créé avec succès."

# Appliquer le RoleBinding
echo "Application du RoleBinding..."
kubectl apply -f gitlab-cicd-rolebinding.yaml

echo "RoleBinding gitlab-cicd-rolebinding appliqué."
kubectl describe rolebinding gitlab-cicd-rolebinding -n $NAMESPACE


echo "Configuration du compte de service $SA_NAME terminée avec succès !"
echo "Fichiers générés : gitlab-sa.yaml, gitlab-sa-token.yaml, gitlab.conf, gitlab-cicd-role.yaml, gitlab-cicd-rolebinding.yaml"
echo "Le token du ServiceAccount est stocké dans gitlab.conf et peut être utilisé pour l'intégration CI/CD (par exemple, avec GitLab)."
