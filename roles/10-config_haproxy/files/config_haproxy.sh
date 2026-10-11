#!/bin/bash

# Arrêter le script si une commande échoue
set -e

set -x  # 👈 Ajoute ça pour afficher les commandes exécutées


# === Fonction pour vérifier les erreurs ===
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ Erreur lors de l'étape: $1"
        exit 1
    fi
} 


# === Installer haproxy ===
echo "Installation de haproxy..."
sudo dnf install haproxy -y
check_error "Installer haproxy"


# === Créer une sauvegarde du fichier de configuration existant ===
echo "Sauvegarde du fichier de configuration existant..."
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
check_error "Créer une sauvegarde du fichier de configuration existant"


# === Écrire la nouvelle configuration dans le fichier haproxy.cfg ===
echo "Écriture de la nouvelle configuration..."
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOL
# Section global : Paramètres globaux
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

# Section defaults : Paramètres par défaut pour toutes les sections suivantes
defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Section frontend : Point d'entrée pour les connexions
frontend kubernetes-frontend
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

# Section backend : Liste des serveurs Kubernetes
backend kubernetes-backend
    option httpchk GET /health
    http-check expect status 200
    mode tcp
    option ssl-hello-chk
    # option tcp-check
    balance roundrobin
    server k8s1 192.168.222.98:6443 check fall 3 rise 2
    server k8s2 192.168.222.97:6443 check fall 3 rise 2
EOL
check_error "Écrire la nouvelle configuration dans le fichier haproxy.cfg"


# === Activer et démarrer le service haproxy ===
echo "Démarrage et activer de haproxy..."
sudo systemctl enable --now haproxy
if [ $? -ne 0 ]; then
    echo "Erreur : haproxy n'a pas démarré. Vérifiez avec 'systemctl status haproxy'."
    exit 1
fi

# === Vérifier l'état du service haproxy ===
echo "Vérification de l'état du service haproxy..."
sudo systemctl status haproxy --no-pager
check_error "Vérifier l'état du service haproxy"



echo "✅ Installation et configuration de haproxy terminées avec succès. 🎉"