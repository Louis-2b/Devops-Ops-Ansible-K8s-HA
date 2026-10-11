#!/bin/bash

# Script de configuration RBAC pour utilisateur Kubernetes

set -e  # Arrête le script en cas d'erreur


# Nom de l'utilisateur et role auquel il appartient
USER="bienvenue"
ROLE_NAME="infra-cr"
BINDING_NAME="infra-crb"


#  Vérification que nous sommes connectés au cluster
if ! kubectl cluster-info &>/dev/null; then
    echo "Erreur: Impossible de se connecter au cluster Kubernetes"
    exit 1
fi


# Étape 1 : Créer le fichier ClusterRole $ROLE_NAME.yaml
echo "Création du fichier ClusterRole $ROLE_NAME.yaml..."
cat <<EOF > "$ROLE_NAME.yaml"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole # rôle valable sur tout le cluster
metadata:
  name: $ROLE_NAME
rules:  # règles d'autorisation associées à ce rôle
- apiGroups:
  - ""
  resources:
  - pods
  - services
  verbs: ["*"] # tous les types d'actions sont autorisés (get, list, create, delete, update, etc.)
- apiGroups:  # concerne les ressources comme Deployments et StatefulSets, qui font partie du groupe apps
  - apps
  resources:
  - deployments
  - statefulsets
  verbs:  # l'utilisateur peut lire et créer ces ressources, mais pas les modifier (update) ni les supprimer (delete)
  - get
  - list
  - create
EOF
echo "Fichier $ROLE_NAME.yaml créé avec succès."


# Application du ClusterRole
echo "Application du ClusterRole..."
kubectl apply -f "$ROLE_NAME".yaml
echo "ClusterRole $ROLE_NAME appliqué."


# Vérifier que le ClusterRole existe
echo "Vérification du ClusterRole..."
kubectl get clusterrole "$ROLE_NAME" &>/dev/null || { echo "Erreur : Le ClusterRole $ROLE_NAME n'a pas été trouvé"; exit 1; }
echo "ClusterRole infra-cr trouvé :"
kubectl describe clusterrole $ROLE_NAME




# Étape 2 : Créer le fichier ClusterRoleBinding
echo "Création du fichier ClusterRoleBinding $BINDING_NAME.yaml..."
cat <<EOF > "$BINDING_NAME.yaml"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $BINDING_NAME
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $ROLE_NAME
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: $USER
EOF
echo "Fichier $BINDING_NAME.yaml créé avec succès."


# Appliquer le ClusterRoleBinding
echo "Application du ClusterRoleBinding..."
kubectl apply -f $BINDING_NAME.yaml
echo "ClusterRoleBinding $BINDING_NAME appliqué."


#  Vérifier que le ClusterRoleBinding existe
echo "Vérification du ClusterRoleBinding..."
kubectl get clusterrolebinding "$BINDING_NAME" &>/dev/null || { echo "Erreur : Le ClusterRoleBinding $BINDING_NAME n'a pas été trouvé"; exit 1; }
echo "ClusterRoleBinding infra-crb trouvé :"
kubectl describe clusterrolebinding "$BINDING_NAME"


echo "Configuration RBAC terminée avec succès pour l'utilisateur $USER !"
echo "Les fichiers générés sont $BINDING_NAME.yaml, $ROLE_NAME.yaml"



