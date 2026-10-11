# Collection Ansible `louis2b.kubernetes` : cluster Kubernetes hautement disponible

Rôles Ansible réutilisables pour déployer un cluster Kubernetes (kubeadm) hautement disponible sur
**Rocky Linux 10** et **Debian 13**. Ce dépôt ne fournit **que des rôles** : l'inventaire et les playbooks
d'orchestration restent dans votre propre projet (section G).

## Sommaire

- [A. Présentation](#a-présentation)
- [B. Architecture du cluster](#b-architecture-du-cluster)
- [C. Contenu du dépôt](#c-contenu-du-dépôt)
- [D. Ce qui est installé sur chaque type de nœud](#d-ce-qui-est-installé-sur-chaque-type-de-nœud)
- [E. Déroulement du déploiement](#e-déroulement-du-déploiement)
- [F. Installation avec `requirements.yml`](#f-installation-avec-requirementsyml)
- [G. Utilisation depuis vos playbooks](#g-utilisation-depuis-vos-playbooks)
- [H. Variables et configuration](#h-variables-et-configuration)
- [I. Vérification et dépannage](#i-vérification-et-dépannage)
- [J. Limites connues](#j-limites-connues)

## A. Présentation

**Objectif.** Automatiser, avec des rôles indépendants, la création d'un cluster Kubernetes avec plusieurs
control planes, un endpoint d'API stable et des workers.

**Systèmes pris en charge** : Rocky Linux 10.x et Debian 13 (« trixie »). Chaque rôle qui installe des paquets
refuse de s'exécuter sur un autre système. Architecture x86_64, IPv4.

**Ce que le dépôt installe et configure** : prérequis système, containerd, kubelet/kubeadm/kubectl, HAProxy +
Keepalived (facultatif), `kubeadm init` et `kubeadm join` (control planes puis workers), réseau de pods Flannel.

**Hors périmètre (volontairement)** : mise à jour de version du cluster, retrait de nœuds, sauvegarde d'etcd,
stockage persistant, ingress, services de type LoadBalancer (MetalLB…), supervision, RBAC applicatif, gestion
des noms d'hôtes, de `/etc/hosts` et de l'accès SSH.

**Prérequis**

- Poste de contrôle : `ansible-core` ≥ 2.18 (première version dont les modules s'exécutent sur Python 3.13,
  celui de Debian 13).
- Nœuds : accès SSH avec élévation de privilèges (`become`), faits Ansible collectés (`gather_facts: true`,
  indispensable : les rôles lisent `ansible_facts`), accès Internet sortant vers `download.docker.com`,
  `pkgs.k8s.io`, `registry.k8s.io`, `github.com` et les registres d'images (pas de mode hors ligne).
- Au moins 2 vCPU et 2 Go de RAM par control plane (exigence de kubeadm), noms d'hôtes uniques en minuscules,
  `product_uuid` et adresses MAC uniques.
- Réseau : tous les nœuds se joignent directement ; l'adresse virtuelle (VIP) du rôle `ha` est une IP libre du
  sous-réseau des load balancers.

## B. Architecture du cluster

```
                      kubectl / kubelet / kube-proxy / workers
                                      │
                    kubernetes_api_endpoint  (VIP:6443 ou nom DNS)
                                      │
             ┌────────────────────────┴────────────────────────┐
             │  rôle ha : Keepalived déplace la VIP (VRRP)     │   ← remplaçable par un équilibreur
        load balancer 1  ◄── VRRP unicast ──►  load balancer 2     │     externe (cloud, matériel)
          HAProxy                                HAProxy
             └────────────────────────┬────────────────────────┘
                 sonde HTTPS /livez   │   répartition TCP
          ┌───────────────────────────┼───────────────────────────┐
     control plane 1             control plane 2             control plane 3
     (premier : kubeadm init)    (kubeadm join)              (kubeadm join)
     apiserver, scheduler,       etcd empilé : quorum 2 sur 3, une panne tolérée
     controller-manager, etcd
          └───────────────────────────┬───────────────────────────┘
                              workers (kubeadm join)
                    Flannel (VXLAN) sur tous les nœuds, kube-proxy, CoreDNS
```

Un cluster à plusieurs control planes n'est pas hautement disponible à lui seul. Quatre niveaux sont à distinguer :

| Niveau               | Mécanisme retenu                                                            | Ce qui est toléré                                                                         | Ce qui ne l'est pas                                                                                                         |
| -------------------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| 1. Control plane     | 3 control planes (ou 5), etcd empilé (quorum)                               | Panne d'un control plane sur 3                                                            | Panne de 2 sur 3 : etcd perd son quorum, l'API devient indisponible. **Avec 2 control planes, aucune panne n'est tolérée.** |
| 2. Endpoint de l'API | Au choix, voir ci-dessous                                                   | Panne d'un load balancer ou d'un control plane sans changement d'adresse pour les clients | Un endpoint unique (une seule IP de control plane) : point de défaillance                                                   |
| 3. Réseau de données | Flannel : un agent par nœud, pas de composant central ; kube-proxy par nœud | Panne d'un nœud : seuls ses pods sont perdus et replanifiés                               | Pas de NetworkPolicy ; pas de chiffrement du trafic entre pods                                                              |
| 4. Stockage          | **Hors périmètre**                                                          | —                                                                                         | À traiter séparément (CSI, stockage répliqué)                                                                               |

**Choix de l'endpoint de l'API** (`kubernetes_api_endpoint`, immuable après `kubeadm init`) :

| Option                                     | Description                                                                                                                                                     | Prérequis et conséquences                                                                                                                                                                                                                                                |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **1. Rôle `ha`** (HAProxy + Keepalived)    | VIP VRRP portée par un des load balancers, HAProxy répartit sur les control planes. Sur ≥ 2 hôtes dédiés, ou sur les control planes avec `ha_bind_port` ≠ 6443. | VIP libre dans un sous-réseau commun aux load balancers ; VRRP (protocole IP 112) autorisé entre eux. Basculement en quelques secondes. Sur un cloud, la VIP doit être autorisée sur les ports réseau (OpenStack : `allowed_address_pairs`) ; sinon utiliser l'option 2. |
| **2. Équilibreur externe**                 | Octavia, ELB/NLB, F5, HAProxy existant… ou un nom DNS                                                                                                           | Ne pas utiliser le rôle `ha` ; renseigner `kubernetes_api_endpoint` avec son adresse. L'équilibreur doit sonder `/livez` en HTTPS sur chaque control plane et être lui-même redondant.                                                                                   |
| **3. Nom DNS à enregistrements multiples** | Un nom résolvant vers tous les control planes                                                                                                                   | Pas de détection de panne : les clients retentent. Déconseillé en production.                                                                                                                                                                                            |

Le dépôt ne déploie qu'une seule solution (option 1) ; les options 2 et 3 consistent simplement à ne pas appeler `ha`.

Composants obligatoires : `prerequisites`, `container_runtime`, `packages`, `control_plane`, `worker`, `cni`.
Dépend de l'architecture : `ha` (option 1 uniquement).

## C. Contenu du dépôt

C'est une **collection Ansible** (et non un rôle unique) : un dépôt Git qui contient plusieurs rôles ne peut pas être
installé rôle par rôle avec `ansible-galaxy role install`. Une collection s'installe depuis Git avec `requirements.yml`,
se verrouille par tag, déclare ses dépendances (`galaxy.yml`) et expose chaque rôle sous son nom complet
`louis2b.kubernetes.<rôle>`. Le namespace `louis2b` est modifiable dans `galaxy.yml` (et dans les `dependencies`
des fichiers `roles/*/meta/main.yml`).

```
galaxy.yml                  métadonnées, version et dépendances de la collection
meta/runtime.yml            version minimale d'ansible-core
CHANGELOG.md                historique des versions (à lire avant de changer de tag)
.ansible-lint, .yamllint    règles de qualité (profil production)
.github/workflows/lint.yml  CI : construction de la collection, yamllint, ansible-lint
.gitignore
roles/
├── prerequisites/          swap, SELinux, modules noyau, sysctl, paquets réseau, chrony, firewalld
│   ├── defaults/ vars/{RedHat,Debian}.yml tasks/{main,firewall}.yml meta/{main,argument_specs}.yml
├── container_runtime/      dépôt Docker CE, containerd.io 2.x, config.toml, crictl
│   ├── defaults/ vars/ tasks/ templates/config.toml.j2 handlers/ meta/
├── packages/               dépôt pkgs.k8s.io, kubelet / kubeadm / kubectl épinglés
│   ├── defaults/ tasks/ meta/
├── ha/                     HAProxy + Keepalived (facultatif)
│   ├── defaults/ vars/ tasks/ templates/{haproxy.cfg,keepalived.conf}.j2 handlers/ meta/
├── control_plane/          kubeadm init (premier nœud) puis kubeadm join (suivants)
│   ├── defaults/ tasks/{main,primary,secondary,kubeconfig}.yml
│   │   templates/{kubeadm-config,kubeadm-join}.yaml.j2 meta/
├── worker/                 kubeadm join des workers
│   ├── defaults/ tasks/ templates/kubeadm-join.yaml.j2 meta/
└── cni/                    Flannel
    ├── defaults/ tasks/ meta/
```

Dans chaque rôle : `defaults/main.yml` contient les valeurs par défaut, `meta/argument_specs.yml` documente et valide
les variables (Ansible refuse de démarrer si une variable obligatoire manque ou a un mauvais type),
`meta/main.yml` déclare les dépendances, `vars/` contient les noms de paquets et d'URL propres à chaque famille de systèmes.

## D. Ce qui est installé sur chaque type de nœud

| Composant                                                                                      | Rôle du composant                                                                      | Tous les nœuds K8s | Premier control plane | Autres control planes | Workers | Load balancers | Rôle Ansible                                     |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | :----------------: | :-------------------: | :-------------------: | :-----: | :------------: | ------------------------------------------------ |
| Swap désactivé, modules `overlay` et `br_netfilter`, sysctl (`ip_forward`, `bridge-nf-call-*`) | Prérequis kubelet et réseau des pods                                                   |         ✔          |           ✔           |           ✔           |    ✔    |                | `prerequisites`                                  |
| `chrony`                                                                                       | Horloge synchronisée (certificats)                                                     |         ✔          |           ✔           |           ✔           |    ✔    |                | `prerequisites`                                  |
| SELinux `permissive` (Rocky)                                                                   | Compatibilité kubeadm                                                                  |         ✔          |           ✔           |           ✔           |    ✔    |                | `prerequisites`                                  |
| firewalld : 10250/tcp, 8472/udp, zone trusted pour pods et services                            | Kubelet, VXLAN Flannel                                                                 |         ✔          |           ✔           |           ✔           |    ✔    |                | `prerequisites`                                  |
| `conntrack`, `socat`, `iptables`, `iproute` (noms selon le système)                            | Dépendances de kubeadm et kube-proxy                                                   |         ✔          |           ✔           |           ✔           |    ✔    |                | `prerequisites`                                  |
| `containerd.io` 2.x + `/etc/containerd/config.toml` + `crictl.yaml`                            | Runtime de conteneurs (CRI)                                                            |         ✔          |           ✔           |           ✔           |    ✔    |                | `container_runtime`                              |
| `kubelet`, `kubeadm`                                                                           | Agent de nœud, outil de création du cluster                                            |         ✔          |           ✔           |           ✔           |    ✔    |                | `packages`                                       |
| `kubectl`                                                                                      | Client en ligne de commande (désactivable sur les workers : `packages_kubectl: false`) |         ✔          |           ✔           |           ✔           |    ✔    |                | `packages`                                       |
| Ports 6443/tcp et 2379-2380/tcp                                                                | API et pairs etcd                                                                      |                    |           ✔           |           ✔           |         |                | `control_plane`                                  |
| `kube-apiserver`, `etcd`, `kube-controller-manager`, `kube-scheduler` (pods statiques)         | Plan de contrôle                                                                       |                    |           ✔           |           ✔           |         |                | `control_plane` (via kubeadm)                    |
| Fichier `~/.kube/config` (si `control_plane_kubeconfig_user`)                                  | Accès administrateur                                                                   |                    |           ✔           |           ✔           |         |                | `control_plane`                                  |
| Port 30000-32767/tcp                                                                           | Plage des NodePort                                                                     |                    |                       |                       |    ✔    |                | `worker`                                         |
| `kube-proxy`, CoreDNS                                                                          | Services et DNS du cluster (créés par kubeadm)                                         |         ✔          |           ✔           |           ✔           |    ✔    |                | `control_plane` (via kubeadm)                    |
| Flannel (DaemonSet `kube-flannel-ds`)                                                          | Réseau des pods                                                                        |         ✔          |           ✔           |           ✔           |    ✔    |                | `cni` (appliqué depuis le premier control plane) |
| `haproxy`                                                                                      | Répartition TCP vers les control planes                                                |                    |                       |                       |         |       ✔        | `ha`                                             |
| `keepalived`                                                                                   | VIP en VRRP unicast, sonde du processus HAProxy                                        |                    |                       |                       |         |       ✔        | `ha`                                             |
| `ip_nonlocal_bind`, port de l'API et protocole VRRP dans firewalld                             | Écoute sur la VIP, trafic autorisé                                                     |                    |                       |                       |         |       ✔        | `ha`                                             |

Les dépendances (`meta/main.yml`) : `control_plane` et `worker` exécutent d'abord `prerequisites`, `container_runtime`
et `packages` (une seule fois par hôte). `ha` et `cni` n'ont pas de dépendance.

## E. Déroulement du déploiement

Les étapes 2 à 4 sont réalisées automatiquement par les dépendances de `control_plane` et `worker` ; elles sont listées
séparément pour savoir ce qui se passe et dans quel ordre.

| #   | Étape                   | Rôle                          | Machines                                        | Prérequis                                                                    | Variables à définir                                                                | Résultat attendu                                                                                             |
| --- | ----------------------- | ----------------------------- | ----------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| 1   | Préparer les machines   | _(hors dépôt)_                | Toutes                                          | Système installé, SSH, `sudo`, noms d'hôtes uniques, horloge, accès Internet | —                                                                                  | Ansible joint chaque hôte                                                                                    |
| 2   | Prérequis système       | `prerequisites`               | Control planes, workers                         | —                                                                            | `kubernetes_pod_cidr`, `kubernetes_service_cidr`, `prerequisites_*` (facultatives) | Swap off, modules et sysctl actifs, ports ouverts                                                            |
| 3   | containerd              | `container_runtime`           | Control planes, workers                         | Étape 2                                                                      | `container_runtime_version` (facultative)                                          | Service `containerd` actif, CRI en cgroups systemd                                                           |
| 4   | Paquets Kubernetes      | `packages`                    | Control planes, workers                         | Étape 3                                                                      | `kubernetes_version`                                                               | `kubelet`, `kubeadm`, `kubectl` à la version exacte                                                          |
| 5   | Endpoint de l'API       | `ha`                          | Load balancers (option 1)                       | Au moins 2 hôtes, VIP libre                                                  | `ha_vip_address`, `ha_peers_group`                                                 | La VIP est portée par un load balancer ; elle écoute sur `ha_bind_port` (aucun backend sain avant l'étape 6) |
| 6   | Premier control plane   | `control_plane`               | Tous les control planes (le premier initialise) | Étape 5 ou équilibreur externe joignable                                     | `kubernetes_api_endpoint`                                                          | `kubeadm init` terminé, `admin.conf` présent, API joignable via l'endpoint                                   |
| 7   | Control planes suivants | `control_plane`               | Même exécution que l'étape 6                    | Étape 6 terminée sur le premier nœud                                         | _(idem)_                                                                           | Les autres control planes rejoignent un à un ; etcd compte N membres                                         |
| 8   | Réseau de pods          | `cni`                         | Un control plane initialisé                     | Étape 6                                                                      | `kubernetes_pod_cidr` (identique à l'étape 2), `cni_flannel_version`               | Flannel déployé, nœuds `Ready`                                                                               |
| 9   | Workers                 | `worker`                      | Workers                                         | Étape 6 ; idéalement 8                                                       | `kubernetes_api_endpoint`                                                          | Les workers rejoignent le cluster                                                                            |
| 10  | Vérification            | _(commandes de la section I)_ | Un control plane                                | Étapes 6 à 9                                                                 | —                                                                                  | Nœuds `Ready`, pods système `Running`, bascules testées                                                      |

Deux contraintes d'ordre expliquent la présence de plusieurs plays (section G) : les control planes et workers
suivants créent leur jeton sur le premier control plane, qui doit donc être initialisé ; et `cni` s'applique avec
le `admin.conf` créé par `kubeadm init`. À l'étape 7, le rôle joint les control planes **un par un** (`throttle: 1`)
avec une clé de certificats commune, et exige la stratégie `linear` (celle par défaut).

Le rôle est **relançable** : un nœud déjà membre du cluster est ignoré, jamais réinitialisé. Si une initialisation ou une
jonction a été interrompue, le rôle s'arrête avec un message explicite (`kubeadm reset -f` puis relance) au lieu de
poursuivre sur un état incohérent.

## F. Installation avec `requirements.yml`

Le dépôt qui **fournit** les rôles (celui-ci) est distinct du projet qui les **consomme** (le vôtre : inventaire,
variables, playbooks). Le projet consommateur déclare la collection dans son propre `requirements.yml` :

```yaml
---
# requirements.yml du PROJET CONSOMMATEUR : URL et version sont des exemples à remplacer.
collections:
  - name: https://github.com/Louis-2b/Devops-Ops-Ansible-K8s-HA.git
    type: git
    version: v1.0.0 # tag, branche ou commit : un tag verrouille la version des rôles
```

```bash
ansible-galaxy collection install -r requirements.yml          # installe aussi ansible.posix et community.general
ansible-galaxy collection install -r requirements.yml --force  # après un changement de version
```

Les collections tierces nécessaires (`ansible.posix`, `community.general`) sont installées automatiquement grâce aux
`dependencies` de `galaxy.yml`. Le tag `v1.0.0` n'existe qu'une fois créé dans le dépôt (`git tag v1.0.0 && git push --tags`) ;
tant qu'il n'existe pas, utilisez le nom d'une branche. Pour un usage local sans Git :
`ansible-galaxy collection build` puis `ansible-galaxy collection install louis2b-kubernetes-1.0.0.tar.gz`.

## G. Utilisation depuis vos playbooks

> Ces fichiers sont des **exemples d'intégration** à adapter (adresses, groupes, accès SSH, secrets) ; ils ne sont pas
> fournis par le dépôt et ne constituent pas une procédure prête à l'emploi.

Inventaire (exemple, adresses de documentation à remplacer) :

```yaml
all:
  children:
    load_balancer:
      hosts:
        lb1: { ansible_host: 192.0.2.11 }
        lb2: { ansible_host: 192.0.2.12 }
    control_plane:
      hosts:
        k8s1: { ansible_host: 192.0.2.31 }
        k8s2: { ansible_host: 192.0.2.32 }
        k8s3: { ansible_host: 192.0.2.33 }
    worker_node:
      hosts:
        node1: { ansible_host: 192.0.2.51 }
        node2: { ansible_host: 192.0.2.52 }
```

`group_vars/all.yml` :

```yaml
kubernetes_version: "1.36.5"
ha_vip_address: 192.0.2.10
kubernetes_api_endpoint: "{{ ha_vip_address }}:6443"
# Facultatif : valeurs par défaut, à fixer si votre plan d'adressage l'exige.
kubernetes_pod_cidr: 10.244.0.0/16
kubernetes_service_cidr: 10.96.0.0/12
# ha_auth_pass: "{{ vault_ha_auth_pass }}"   # secret : dans Ansible Vault
```

`site.yml` :

```yaml
---
- name: Endpoint API hautement disponible (option 1 ; supprimer ce play avec un équilibreur externe)
  hosts: load_balancer
  become: true
  roles:
    - louis2b.kubernetes.ha

- name: Control planes (le premier initialise, les suivants rejoignent un par un)
  hosts: control_plane
  become: true
  roles:
    - louis2b.kubernetes.control_plane

- name: Réseau de pods (depuis un control plane initialisé)
  hosts: control_plane[0]
  become: true
  roles:
    - louis2b.kubernetes.cni

- name: Workers
  hosts: worker_node
  become: true
  roles:
    - louis2b.kubernetes.worker
```

```bash
ansible-playbook -i inventory.yml site.yml --ask-vault-pass
```

Points d'attention : `gather_facts` doit rester actif ; ne limitez pas l'exécution du play `control_plane` à un
sous-ensemble sauf pour ajouter un nœud (`--limit k8s4` fonctionne : le jeton est créé sur le premier control plane) ;
pour ajouter un control plane, ajoutez-le à l'inventaire puis relancez ce play. Le premier control plane est le premier
hôte du groupe par ordre alphabétique : si le nom du nouveau nœud précède les autres, fixez explicitement
`kubernetes_primary_control_plane: k8s1` (le rôle refuse de toute façon d'exécuter `kubeadm init` si un serveur répond
déjà sur l'endpoint). Si HAProxy est installé **sur** les
control planes, utilisez `ha_peers_group: control_plane` et `ha_bind_port: 8443` (l'API écoute déjà sur 6443), et
mettez `kubernetes_api_endpoint: "{{ ha_vip_address }}:8443"`.

## H. Variables et configuration

Convention : `kubernetes_*` = variable **partagée** entre plusieurs rôles (définissez-la une seule fois, dans
`group_vars/all`) ; `<rôle>_*` = variable propre à un rôle. Les valeurs par défaut d'une variable partagée sont
identiques dans chaque rôle qui la définit. Les tableaux ci-dessous sont générés à partir de `meta/argument_specs.yml`.

### Variables communes (cluster)

| Variable                           | Défaut                                        | Rôles                                   | Description                                                                                                              |
| ---------------------------------- | --------------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `kubernetes_version`               | `1.36.5`                                      | `packages`, `control_plane`             | Version exacte x.y.z des paquets et du control plane. Ne la modifiez pas sur un cluster existant (voir J).               |
| `kubernetes_api_endpoint`          | **obligatoire**                               | `control_plane`, `worker`               | `hôte:port` stable de l'API. Immuable après `kubeadm init`.                                                              |
| `kubernetes_pod_cidr`              | `10.244.0.0/16`                               | `prerequisites`, `control_plane`, `cni` | Réseau des pods. Doit être identique partout.                                                                            |
| `kubernetes_service_cidr`          | `10.96.0.0/12`                                | `prerequisites`, `control_plane`        | Réseau des services.                                                                                                     |
| `kubernetes_control_plane_group`   | `control_plane`                               | `control_plane`, `worker`, `ha`         | Nom du groupe d'inventaire des control planes.                                                                           |
| `kubernetes_primary_control_plane` | premier hôte du groupe par ordre alphabétique | `control_plane`, `worker`               | Nœud qui exécute `kubeadm init` ; le choix ne dépend pas de l'ordre de l'inventaire.                                     |
| `kubernetes_node_ip`               | adresse de la route par défaut de l'hôte      | `control_plane`, `worker`, `ha`         | À définir **par hôte** si l'IP du cluster diffère de la route par défaut (plusieurs cartes réseau) ou de `ansible_host`. |

### Prérequis système (`prerequisites`) : tous les nœuds Kubernetes

| Variable                         | Défaut                                                                                                                                                                                        | Description                                                                                               |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `kubernetes_pod_cidr`            | `10.244.0.0/16`                                                                                                                                                                               | Réseau des pods (CIDR). Placé dans la zone firewalld trusted ; identique à celui de control_plane et cni. |
| `kubernetes_service_cidr`        | `10.96.0.0/12`                                                                                                                                                                                | Réseau des services (CIDR). Placé dans la zone firewalld trusted ; identique à celui de control_plane.    |
| `prerequisites_time_sync_manage` | `true`                                                                                                                                                                                        | Installer et activer chrony.                                                                              |
| `prerequisites_selinux_state`    | `permissive`                                                                                                                                                                                  | État SELinux sur Rocky (sans effet sur Debian). Valeurs : `permissive`, `enforcing`, `disabled`.          |
| `prerequisites_kernel_modules`   | `["overlay", "br_netfilter"]`                                                                                                                                                                 | Modules noyau chargés et rendus persistants.                                                              |
| `prerequisites_sysctl`           | `{"net.bridge.bridge-nf-call-iptables": 1, "net.bridge.bridge-nf-call-ip6tables": 1, "net.ipv4.ip_forward": 1, "fs.inotify.max_user_instances": 8192, "fs.inotify.max_user_watches": 524288}` | Paramètres sysctl appliqués.                                                                              |
| `prerequisites_firewall_manage`  | `{{ ansible_facts['os_family'] == 'RedHat' }}`                                                                                                                                                | Gérer firewalld (installation, ports, zone trusted). Par défaut true sur Rocky, false sur Debian.         |
| `prerequisites_firewall_zone`    | `""`                                                                                                                                                                                          | Zone firewalld à configurer ; vide = zone par défaut.                                                     |
| `prerequisites_firewall_ports`   | `["10250/tcp", "8472/udp"]`                                                                                                                                                                   | Ports ouverts sur tous les nœuds (kubelet, VXLAN Flannel).                                                |

### containerd (`container_runtime`)

| Variable                          | Défaut                                   | Description                                                                              |
| --------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------- |
| `container_runtime_version`       | `""`                                     | Version exacte de containerd.io (ex. 2.3.6) ; vide = dernière du dépôt à l'installation. |
| `container_runtime_socket`        | `unix:///run/containerd/containerd.sock` | Socket CRI utilisé par kubeadm, kubelet et crictl.                                       |
| `container_runtime_sandbox_image` | `""`                                     | Image pause (sandbox) ; vide = valeur par défaut de containerd.                          |

### Paquets Kubernetes (`packages`)

| Variable             | Défaut   | Description                                                 |
| -------------------- | -------- | ----------------------------------------------------------- |
| `kubernetes_version` | `1.36.5` | Version Kubernetes exacte x.y.z (paquets et control plane). |
| `packages_kubectl`   | `true`   | Installer kubectl (obligatoire sur les control planes).     |

### Haute disponibilité de l'endpoint (`ha`) : load balancers

| Variable               | Défaut                                                                          | Description                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `ha_vip_address`       | **obligatoire**                                                                 | Adresse IP virtuelle de l'API Kubernetes, libre dans le sous-réseau des load balancers.                                                        |
| `ha_peers_group`       | `load_balancer`                                                                 | Groupe d'inventaire des hôtes qui reçoivent ce rôle (au moins 2).                                                                              |
| `ha_backend_group`     | `{{ kubernetes_control_plane_group \| default('control_plane') }}`              | Groupe d'inventaire des control planes (backends HAProxy).                                                                                     |
| `ha_bind_port`         | `6443`                                                                          | Port d'écoute de HAProxy sur la VIP (port de kubernetes_api_endpoint). Doit différer de ha_backend_port si HAProxy est sur les control planes. |
| `ha_backend_port`      | `6443`                                                                          | Port de kube-apiserver sur les control planes.                                                                                                 |
| `ha_vip_prefix`        | `32`                                                                            | Longueur de préfixe de la VIP.                                                                                                                 |
| `ha_vip_interface`     | `{{ ansible_facts['default_ipv4']['interface'] }}`                              | Interface portant la VIP.                                                                                                                      |
| `ha_node_ip`           | `{{ kubernetes_node_ip \| default(ansible_facts['default_ipv4']['address']) }}` | Adresse de ce nœud dans le groupe VRRP.                                                                                                        |
| `ha_virtual_router_id` | `51`                                                                            | Identifiant VRRP (1-255), unique par segment réseau.                                                                                           |
| `ha_priority`          | _voir description_                                                              | Priorité VRRP ; le plus haut détient la VIP. Par défaut : ordre alphabétique des hôtes.                                                        |
| `ha_auth_pass`         | `""`                                                                            | Mot de passe VRRP (8 caractères significatifs) ; vide = sans authentification. Sensible : Ansible Vault.                                       |
| `ha_maxconn`           | `4096`                                                                          | Connexions maximales de HAProxy.                                                                                                               |
| `ha_balance`           | `roundrobin`                                                                    | Algorithme de répartition HAProxy.                                                                                                             |
| `ha_timeout_connect`   | `5s`                                                                            | Délai de connexion.                                                                                                                            |
| `ha_timeout_client`    | `1h`                                                                            | Délai d'inactivité côté client.                                                                                                                |
| `ha_timeout_server`    | `1h`                                                                            | Délai d'inactivité côté serveur.                                                                                                               |
| `ha_check_interval`    | `3s`                                                                            | Intervalle des sondes de santé.                                                                                                                |
| `ha_check_fall`        | `3`                                                                             | Échecs consécutifs avant de retirer un control plane.                                                                                          |
| `ha_check_rise`        | `2`                                                                             | Succès consécutifs avant de le réintégrer.                                                                                                     |
| `ha_firewall_manage`   | `{{ ansible_facts['os_family'] == 'RedHat' }}`                                  | Gérer firewalld (port de l'API et VRRP). Par défaut true sur Rocky.                                                                            |
| `ha_firewall_zone`     | `""`                                                                            | Zone firewalld ; vide = zone par défaut.                                                                                                       |

### Control planes (`control_plane`)

| Variable                           | Défaut                                                                          | Description                                                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `kubernetes_api_endpoint`          | **obligatoire**                                                                 | Adresse stable de l'API « hôte:port » (VIP, nom DNS ou équilibreur externe). Immuable après kubeadm init. |
| `kubernetes_control_plane_group`   | `control_plane`                                                                 | Groupe d'inventaire des control planes.                                                                   |
| `kubernetes_primary_control_plane` | `{{ groups[kubernetes_control_plane_group] \| sort \| first }}`                 | Nœud qui exécute kubeadm init.                                                                            |
| `kubernetes_pod_cidr`              | `10.244.0.0/16`                                                                 | Réseau des pods (CIDR).                                                                                   |
| `kubernetes_service_cidr`          | `10.96.0.0/12`                                                                  | Réseau des services (CIDR).                                                                               |
| `control_plane_node_ip`            | `{{ kubernetes_node_ip \| default(ansible_facts['default_ipv4']['address']) }}` | Adresse du nœud dans le cluster (kubelet, etcd, kube-apiserver).                                          |
| `control_plane_cluster_name`       | `kubernetes`                                                                    | Nom du cluster.                                                                                           |
| `control_plane_dns_domain`         | `cluster.local`                                                                 | Domaine DNS du cluster.                                                                                   |
| `control_plane_bind_port`          | `6443`                                                                          | Port de kube-apiserver sur chaque control plane.                                                          |
| `control_plane_extra_sans`         | `[]`                                                                            | Noms ou IP supplémentaires du certificat de l'API.                                                        |
| `control_plane_kube_proxy_mode`    | `iptables`                                                                      | Mode de kube-proxy. Valeurs : `iptables`, `nftables`, `ipvs`.                                             |
| `control_plane_token_ttl`          | `1h`                                                                            | Durée de vie du jeton de jonction.                                                                        |
| `control_plane_kubeconfig_user`    | `""`                                                                            | Compte Linux qui reçoit ~/.kube/config ; vide = aucun.                                                    |
| `control_plane_firewall_ports`     | `["{{ control_plane_bind_port }}/tcp", "2379-2380/tcp"]`                        | Ports ouverts sur les control planes.                                                                     |

### Workers (`worker`)

| Variable                           | Défaut                                                                          | Description                                                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `kubernetes_api_endpoint`          | **obligatoire**                                                                 | Adresse stable de l'API « hôte:port » (VIP, nom DNS ou équilibreur externe). Immuable après kubeadm init. |
| `kubernetes_control_plane_group`   | `control_plane`                                                                 | Groupe d'inventaire des control planes.                                                                   |
| `kubernetes_primary_control_plane` | `{{ groups[kubernetes_control_plane_group] \| sort \| first }}`                 | Nœud qui exécute kubeadm init.                                                                            |
| `worker_node_ip`                   | `{{ kubernetes_node_ip \| default(ansible_facts['default_ipv4']['address']) }}` | Adresse du nœud dans le cluster.                                                                          |
| `worker_token_ttl`                 | `30m`                                                                           | Durée de vie du jeton de jonction.                                                                        |
| `worker_firewall_ports`            | `["30000-32767/tcp"]`                                                           | Ports ouverts sur les workers (plage NodePort).                                                           |

### Réseau de pods (`cni`)

| Variable                        | Défaut                                                                                               | Description                                                    |
| ------------------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `kubernetes_pod_cidr`           | `10.244.0.0/16`                                                                                      | Réseau des pods ; doit être identique au podSubnet du cluster. |
| `cni_flannel_version`           | `v0.28.10`                                                                                           | Version de Flannel.                                            |
| `cni_flannel_manifest_url`      | `https://github.com/flannel-io/flannel/releases/download/{{ cni_flannel_version }}/kube-flannel.yml` | URL du manifeste (surchargeable pour un miroir interne).       |
| `cni_flannel_manifest_checksum` | `""`                                                                                                 | Empreinte du manifeste (ex. sha256:…) ; vide = non vérifié.    |
| `cni_manifest_dir`              | `/etc/kubernetes/addons`                                                                             | Répertoire de stockage du manifeste sur le nœud.               |
| `cni_rollout_timeout`           | `300s`                                                                                               | Délai d'attente du déploiement.                                |

### Paramètres sensibles

- `ha_auth_pass` : mot de passe VRRP, vide par défaut (pas d'authentification) ; à placer dans Ansible Vault si utilisé.
- Les jetons de jonction et la clé de certificats ne sont **jamais stockés** : créés à la demande sur le premier control plane
  (TTL `control_plane_token_ttl` / `worker_token_ttl`), écrits dans un fichier `0600` supprimé dès la fin de `kubeadm join`,
  et masqués dans les journaux (`no_log`). La clé de certificats téléversée par `kubeadm` expire au bout de 2 heures.
- `/etc/kubernetes/admin.conf` donne les droits d'administrateur du cluster : lisible par root uniquement.

## I. Vérification et dépannage

À exécuter sur un control plane (`sudo -i` ou `export KUBECONFIG=/etc/kubernetes/admin.conf`).

**Services système** (sur chaque nœud concerné)

```bash
systemctl is-active containerd kubelet            # tous les nœuds
systemctl is-active haproxy keepalived            # load balancers
journalctl -u kubelet -n 50 --no-pager            # raisons d'un nœud NotReady
crictl ps                                         # conteneurs en cours (config /etc/crictl.yaml)
```

**Nœuds et control plane**

```bash
kubectl get nodes -o wide                         # tous Ready, versions identiques
kubectl -n kube-system get pods -o wide           # apiserver, etcd, scheduler, controller-manager de chaque control plane
kubectl get --raw='/readyz?verbose' | tail -n 5
kubectl -n kube-system exec etcd-<nom-du-control-plane> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --cluster -w table              # N membres, un leader
```

**CNI**

```bash
kubectl -n kube-flannel get daemonset,pods -o wide   # un pod par nœud, Running
kubectl -n kube-system get pods -l k8s-app=kube-dns  # CoreDNS Running
```

**Accessibilité de l'endpoint**

```bash
curl -ks https://<endpoint>/livez ; echo                       # ok
ip -brief addr | grep <VIP>                                    # sur le load balancer qui porte la VIP
```

**Tolérance aux pannes** (à faire avant la mise en production, hors heures ouvrées)

1. _Load balancer_ : sur celui qui porte la VIP, `systemctl stop haproxy` (la sonde Keepalived retire la VIP en quelques
   secondes) ; `curl -ks https://<endpoint>/livez` doit rester `ok` ; puis `systemctl start haproxy`.
2. _Control plane_ : éteindre un control plane ; `kubectl get nodes` (via l'endpoint) doit répondre, HAProxy retire le nœud
   après `ha_check_fall` × `ha_check_interval`. Éteindre un second control plane sur 3 doit, lui, faire perdre le quorum :
   c'est le comportement attendu.

**Erreurs fréquentes**

| Symptôme                                                                   | Cause probable                                         | Action                                                                                 |
| -------------------------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| `kubernetes_api_endpoint` ou `ha_vip_address` « is undefined »             | Variable obligatoire absente                           | La définir dans `group_vars/all`                                                       |
| `ansible_facts['default_ipv4']` introuvable                                | Faits non collectés ou pas de route par défaut         | `gather_facts: true`, ou définir `kubernetes_node_ip` / `ha_vip_interface`             |
| « Système non pris en charge »                                             | Autre distribution ou version                          | Rocky Linux 10 ou Debian 13 uniquement                                                 |
| « Kubernetes 1.36 exige containerd 2.x »                                   | Dépôt ou version épinglée en 1.x                       | Vérifier `container_runtime_version`                                                   |
| `crictl` : `unknown service runtime.v1.RuntimeService`                     | Plugin CRI désactivé (config livrée par le paquet)     | Relancer `container_runtime` (réécrit `/etc/containerd/config.toml`)                   |
| `kubeadm init` : timeout sur l'endpoint                                    | VIP injoignable, pare-feu, `ha` non appliqué           | `curl -k https://<endpoint>/livez`, vérifier VRRP et le pare-feu                       |
| HAProxy refuse de démarrer, port 6443 occupé                               | HAProxy sur un control plane avec `ha_bind_port: 6443` | Utiliser un autre port (ex. 8443) et le reporter dans l'endpoint                       |
| « initialisation incomplète » / « jonction interrompue »                   | `kubeadm` interrompu                                   | Suivre le message : `kubeadm reset -f` (et retirer le membre etcd si besoin), relancer |
| `token ... not found` / jonction refusée                                   | Jeton ou clé de certificats expirés (TTL, 2 h)         | Relancer le rôle : un nouveau jeton est créé                                           |
| Nœuds `NotReady`, pods `ContainerCreating`                                 | CNI absent ou ports 8472/udp bloqués                   | Appliquer `cni`, ouvrir 8472/udp entre nœuds (groupes de sécurité compris)             |
| Certificats invalides, `x509: certificate has expired or is not yet valid` | Horloges désynchronisées                               | `chronyc tracking` sur chaque nœud                                                     |
| Deux load balancers portent la VIP                                         | VRRP bloqué entre eux (protocole 112)                  | Autoriser VRRP, vérifier `unicast_peer` dans `/etc/keepalived/keepalived.conf`         |

## J. Limites connues

**Vérifications effectuées pour ce dépôt**

- Lecture et analyse de l'ancien dépôt ; chargement de tous les fichiers YAML ; rendu avec Jinja2 de `haproxy.cfg`,
  `keepalived.conf`, `kubeadm-config`, des deux `kubeadm-join` et de `config.toml` (TOML validé, documents kubeadm lus
  comme YAML) ; test des expressions de sélection (premier control plane, nœuds à joindre, priorités VRRP, noms de paquets).
- Disponibilité vérifiée sur les sources officielles : `containerd.io` 2.x dans `download.docker.com` pour `rhel/10` et
  Debian trixie ; `haproxy` 3.0 et `keepalived` dans AppStream Rocky 10 (builds `el10_2` présents) ; `haproxy` 3.0 présent dans Debian 13 et
  `keepalived` (2.3.x) dans le pool Debian ; Kubernetes 1.36.5 publié ; `kube-flannel.yml` joint à la version v0.28.10 de Flannel.

**Non réalisé (à faire avant la production)**

- **Aucune exécution sur de vraies machines** Rocky Linux 10.2 ou Debian 13 : aucun cluster n'a été créé avec ce code.
- `ansible-lint`, `ansible-playbook --syntax-check` et Molecule n'ont pas pu être exécutés (pas d'accès à PyPI depuis l'environnement
  de rédaction). La CI (`.github/workflows/lint.yml`) lance la construction de la collection, `yamllint` et `ansible-lint`
  à chaque push ; consultez son résultat.
- L'index `pkgs.k8s.io` n'a pas pu être lu directement : les URL de dépôt suivent la documentation officielle de kubeadm.
- Comportement de SELinux en mode `enforcing` (Rocky) non validé, notamment pour HAProxy sur un port autre que 6443 et pour Keepalived.

**Limites fonctionnelles**

- **Pas de mise à jour du cluster** : modifier `kubernetes_version` sur un cluster existant installe de nouveaux paquets
  sans exécuter `kubeadm upgrade` ; suivez la procédure officielle de mise à niveau, nœud par nœud.
- Pas de retrait de nœud, pas de sauvegarde d'etcd, pas de renouvellement de certificats (kubeadm : validité d'un an).
- etcd empilé : prévoir 3 ou 5 control planes. Les control planes ne portent pas de charges applicatives (taint kubeadm par défaut).
- Flannel : pas de NetworkPolicy, VXLAN uniquement, IPv4 uniquement. Un autre CNI demande un autre rôle.
- Keepalived ne surveille que la présence du processus HAProxy, pas la santé des backends. Si VRRP est bloqué entre les
  deux load balancers, chacun peut porter la VIP.
- containerd n'est pas verrouillé contre les mises à jour automatiques ; kubelet, kubeadm et kubectl le sont (`exclude` dnf, `hold` apt).
- Le nom de l'hôte dans l'inventaire est le nom du nœud Kubernetes : le dépôt ne change ni le nom d'hôte ni `/etc/hosts`.
- Accès Internet requis depuis les nœuds ; pas de miroir hors ligne (seul le manifeste Flannel est surchargeable : `cni_flannel_manifest_url`).
- Sur un cloud (OpenStack…), la VIP du rôle `ha` doit être réservée et autorisée sur les ports des load balancers
  (par exemple `openstack port create` avec `--fixed-ip`, puis `openstack port set --allowed-address ip-address=<VIP>` sur chaque
  port ; à adapter à votre cloud, non testé ici), les groupes de sécurité doivent laisser passer les ports de la section D,
  VRRP et 8472/udp. Sinon, utilisez l'option 2 (équilibreur du cloud).
- Aucune licence n'est déclarée (`license: UNLICENSED` dans `roles/*/meta/main.yml`) : choisissez-en une.
