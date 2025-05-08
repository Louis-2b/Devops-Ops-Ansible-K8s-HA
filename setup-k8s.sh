#!/bin/bash

# Script pour automatiser la configuration d'un namespace, serviceaccount, secret, role et rolebinding dans Kubernetes

# Fonction pour vérifier si une commande a réussi
check_error() {
    if [ $? -ne 0 ]; then
        echo "Erreur lors de l'exécution de la commande précédente. Arrêt du script."
        exit 1
    fi
}

# Étape 1 : Créer le namespace 'my-micro-service'
echo "Création du namespace 'my-micro-service'..."
kubectl create namespace my-micro-service
check_error

# Étape 2 : Créer le ServiceAccount 'cicd-sa' dans le namespace
echo "Création du ServiceAccount 'cicd-sa'..."
kubectl create serviceaccount cicd-sa --namespace=my-micro-service
check_error

# Étape 3 : Créer le fichier cicd-sa-token.yaml
echo "Création du fichier cicd-sa-token.yaml..."
cat << EOF > cicd-sa-token.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cicd-sa-token
  namespace: my-micro-service
  annotations:
    kubernetes.io/service-account.name: cicd-sa
type: kubernetes.io/service-account-token
EOF
check_error

# Étape 4 : Appliquer le fichier cicd-sa-token.yaml
echo "Application du fichier cicd-sa-token.yaml..."
kubectl apply -f cicd-sa-token.yaml
check_error

# Étape 5 : Afficher les détails du ServiceAccount
echo "Affichage des détails du ServiceAccount 'cicd-sa'..."
kubectl describe serviceaccount cicd-sa --namespace=my-micro-service
check_error

# Étape 6 : Lister les secrets dans le namespace
echo "Liste des secrets dans le namespace 'my-micro-service'..."
kubectl get secret --namespace=my-micro-service
check_error

# Étape 7 : Créer le fichier cicd-role.yaml
echo "Création du fichier cicd-role.yaml..."
cat << EOF > cicd-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: my-micro-service
  name: cicd-role
rules:
- apiGroups: [""]
  resources:
  - pods
  - services
  verbs:
  - get
  - watch
  - list
  - create
  - update
  - patch
  - delete
- apiGroups:
  - apps
  resources:
  - deployments
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
EOF
check_error

# Étape 8 : Appliquer le fichier cicd-role.yaml
echo "Application du fichier cicd-role.yaml..."
kubectl apply -f cicd-role.yaml
check_error

# Étape 9 : Créer le fichier cicd-rolebinding.yaml
echo "Création du fichier cicd-rolebinding.yaml..."
cat << EOF > cicd-rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cicd-rolebinding
  namespace: my-micro-service
subjects:
- kind: ServiceAccount
  name: cicd-sa
  namespace: my-micro-service
roleRef:
  kind: Role
  name: cicd-role
  apiGroup: rbac.authorization.k8s.io
EOF
check_error

# Étape 10 : Appliquer le fichier cicd-rolebinding.yaml
echo "Application du fichier cicd-rolebinding.yaml..."
kubectl apply -f cicd-rolebinding.yaml
check_error

# Étape 11 : Copier le fichier kubeconfig
echo "Copie du fichier ~/.kube/config vers ~/cicd-kubeconfig.yaml..."
cp ~/.kube/config ~/cicd-kubeconfig.yaml
check_error

# Étape 12 : Afficher le secret cicd-sa-token
echo "Affichage du secret 'cicd-sa-token' en YAML..."
kubectl get secret cicd-sa-token -n my-micro-service -o yaml
check_error

# Étape 13 : Extraire et décoder le token du secret cicd-sa-token
echo "Extraction et décodage du token du secret 'cicd-sa-token'..."
SECRET="cicd-sa-token"
NAMESPACE="my-micro-service"
TOKEN=$(kubectl get secret "$SECRET" -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 --decode)
check_error
echo "Token décodé : $TOKEN"

echo "Script terminé avec succès !"