#!/bin/bash

# Script pour automatiser l'installation de kube-prometheus-stack avec Helm et Kubernetes

# Arrêter le script en cas d'erreur
set -e


# Définir l'espace de noms et le nom du secret
NAMESPACE="monitoring"
SECRET_NAME="grafana-admin-credentials"
ADMIN_USER="admin"
ADMIN_PASSWORD="P@sswrd2b&!!"


echo "Démarrage de l'installation de la pile de surveillance Prometheus et Grafana..."

# Étape 1 : Vérifier la communication avec le cluster Kubernetes
echo "Vérification des nœuds du cluster Kubernetes..."
kubectl get nodes
if [ $? -ne 0 ]; then
    echo "Erreur : Impossible de communiquer avec le cluster Kubernetes. Arrêt."
    exit 1
fi


# Étape 2 : Vérifier l'installation de Helm
echo "Vérification de la version de Helm..."
helm version
if [ $? -ne 0 ]; then
    echo "Erreur : Helm n'est pas installé ou ne fonctionne pas. Arrêt."
    exit 1
fi


# Étape 3 : Ajouter le dépôt Helm de Prometheus
echo "Ajout du dépôt Helm de Prometheus..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
if [ $? -ne 0 ]; then
    echo "Erreur : Échec de l'ajout du dépôt Helm. Arrêt."
    exit 1
fi


# Étape 4 : Mettre à jour les dépôts Helm
echo "Mise à jour des dépôts Helm..."
helm repo update
if [ $? -ne 0 ]; then
    echo "Erreur : Échec de la mise à jour des dépôts Helm. Arrêt."
    exit 1
fi


# Étape 5 : Créer l'espace de noms Kubernetes
echo "Création de l'espace de noms Kubernetes '$NAMESPACE'..."
kubectl create namespace $NAMESPACE || echo "L'espace de noms '$NAMESPACE' existe déjà."


# Étape 6 : Créer des fichiers pour les identifiants administrateurs
echo "Création des fichiers pour les identifiants administrateurs..."
echo -n $ADMIN_USER > ./admin-user
echo -n $ADMIN_PASSWORD > ./admin-password


# Étape 7 : Créer un secret Kubernetes pour les identifiants Grafana
echo "Création du secret Kubernetes '$SECRET_NAME'..."
kubectl create secret generic $SECRET_NAME --from-file=./admin-user --from-file=admin-password -n $NAMESPACE
if [ $? -ne 0 ]; then
    echo "Erreur : Échec de la création du secret Kubernetes. Arrêt."
    exit 1
fi


# Étape 8 : Vérifier le secret
echo "Vérification du secret '$SECRET_NAME'..."
kubectl describe secret -n $NAMESPACE $SECRET_NAME


# Étape 9 : Vérifier le nom d'utilisateur
echo "Vérification du nom d'utilisateur administrateur..."
kubectl get secret -n $NAMESPACE $SECRET_NAME -o jsonpath="{.data.admin-user}" | base64 --decode
echo ""


# Étape 10 : Vérifier le mot de passe
echo "Vérification du mot de passe administrateur..."
kubectl get secret -n $NAMESPACE $SECRET_NAME -o jsonpath="{.data.admin-password}" | base64 --decode
echo ""


# Étape 11 : Supprimer les fichiers d'identifiants
echo "Suppression des fichiers temporaires d'identifiants..."
sudo rm -rf admin-user admin-password


# Étape 12 : Créer le fichier values.yaml avec la configuration adaptée
echo "Création du fichier values.yaml pour kube-prometheus-stack..."
cat << EOF > values.yaml
fullnameOverride: prometheus

defaultRules:
  create: true
  rules:
    alertmanager: true
    etcd: true
    configReloaders: true
    general: true
    k8s: true
    kubeApiserverAvailability: true
    kubeApiserverBurnrate: true
    kubeApiserverHistogram: true
    kubeApiserverSlos: true
    kubelet: true
    kubeProxy: true
    kubePrometheusGeneral: true
    kubePrometheusNodeRecording: true
    kubernetesApps: true
    kubernetesResources: true
    kubernetesStorage: true
    kubernetesSystem: true
    kubeScheduler: true
    kubeStateMetrics: true
    network: true
    node: true
    nodeExporterAlerting: true
    nodeExporterRecording: true
    prometheus: true
    prometheusOperator: true

alertmanager:
  fullnameOverride: alertmanager
  enabled: true
  ingress:
    enabled: false

grafana:
  enabled: true
  fullnameOverride: grafana
  forceDeployDatasources: false
  forceDeployDashboards: false
  defaultDashboardsEnabled: true
  defaultDashboardsTimezone: utc
  serviceMonitor:
    enabled: true
  admin:
    existingSecret: grafana-admin-credentials
    userKey: admin-user
    passwordKey: admin-password
  service:
    type: LoadBalancer
    port: 80
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/rewrite-target: /
    hosts:
      - grafana.tubie.local
    paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80

kubeApiServer:
  enabled: true

kubelet:
  enabled: true
  serviceMonitor:
    metricRelabelings:
      - action: replace
        sourceLabels:
          - node
        targetLabel: instance

kubeControllerManager:
  enabled: true
  endpoints:
    - 192.168.222.98
    - 192.168.222.97

coreDns:
  enabled: true

kubeDns:
  enabled: false

kubeEtcd:
  enabled: true
  endpoints:
    - 192.168.222.98
    - 192.168.222.97
  service:
    enabled: true
    port: 2381
    targetPort: 2381

kubeScheduler:
  enabled: true
  endpoints:
    - 192.168.222.98
    - 192.168.222.97

kubeProxy:
  enabled: true
  endpoints:
    - 192.168.222.98
    - 192.168.222.97

kubeStateMetrics:
  enabled: true

kube-state-metrics:
  fullnameOverride: kube-state-metrics
  selfMonitor:
    enabled: true
  prometheus:
    monitor:
      enabled: true
      relabelings:
        - action: replace
          regex: (.*)
          replacement: \$1
          sourceLabels:
            - __meta_kubernetes_pod_node_name
          targetLabel: kubernetes_node

nodeExporter:
  enabled: true
  serviceMonitor:
    relabelings:
      - action: replace
        regex: (.*)
        replacement: \$1
        sourceLabels:
          - __meta_kubernetes_pod_node_name
        targetLabel: kubernetes_node

prometheus-node-exporter:
  fullnameOverride: node-exporter
  podLabels:
    jobLabel: node-exporter
  extraArgs:
    - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)
    - --collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)\$
  service:
    portName: http-metrics
  prometheus:
    monitor:
      enabled: true
      relabelings:
        - action: replace
          regex: (.*)
          replacement: \$1
          sourceLabels:
            - __meta_kubernetes_pod_node_name
          targetLabel: kubernetes_node
  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 2048Mi

prometheusOperator:
  enabled: true
  prometheusConfigReloader:
    resources:
      requests:
        cpu: 200m
        memory: 50Mi
      limits:
        memory: 100Mi

prometheus:
  enabled: true
  prometheusSpec:
    replicas: 1
    replicaExternalLabelName: "replica"
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    probeSelectorNilUsesHelmValues: false
    retention: 6h
    enableAdminAPI: true
    walCompression: true
    scrapeInterval: 30s
    evaluationInterval: 30s

thanosRuler:
  enabled: false
EOF




# Étape 13 : Installer ou mettre à jour kube-prometheus-stack
echo "Installation ou mise à jour de kube-prometheus-stack dans l'espace de noms '$NAMESPACE'..."
if helm list -n $NAMESPACE | grep -q prometheus; then
    echo "Une installation existante a été trouvée. Mise à jour de la release 'prometheus'..."
    helm upgrade -n $NAMESPACE prometheus prometheus-community/kube-prometheus-stack -f values.yaml
else
    echo "Installation de la release 'prometheus'..."
    helm install -n $NAMESPACE prometheus prometheus-community/kube-prometheus-stack -f values.yaml
fi
if [ $? -ne 0 ]; then
    echo "Erreur : Échec de l'installation ou de la mise à jour de kube-prometheus-stack. Arrêt."
    exit 1
fi





echo "Installation terminée ! Prometheus et Grafana sont installés dans l'espace de noms '$NAMESPACE'."
