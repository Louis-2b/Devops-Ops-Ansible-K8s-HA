# Cluster Kubernetes haute disponibilité avec Ansible (Rocky Linux 10.2)

Déploie un cluster Kubernetes hautement disponible sur Rocky Linux 10.2 avec des **rôles Ansible
idempotents** (modules natifs `dnf`, `firewalld`, `sysctl`, `template`…), à la place des anciens
scripts bash copiés puis exécutés sur les machines.

## Architecture

```
                        ┌──────────────── VIP 192.168.222.20:6443 ────────────────┐
                        │        (Pacemaker/Corosync : IPaddr2 + HAProxy)         │
                        └──────────────┬───────────────────────────┬──────────────┘
                              haproxy1 (actif)              haproxy2 (secours)
                                       │ répartition TCP + sonde /livez
                  ┌────────────────────┼────────────────────┐
                  ▼                    ▼                    ▼
               k8s1                  k8s2               (k8s3 recommandé)     control plane (kubeadm, etcd empilé)
                  └────────────────────┬────────────────────┘
                                       ▼
                                     node1 …                                 workers
        Réseau pods : Flannel · LoadBalancer : MetalLB (L2) · Ingress : ingress-nginx
        Métriques : metrics-server (HA) · Supervision : kube-prometheus-stack
```

## Ce qui a changé par rapport à la version « scripts »

| Avant                                                                    | Maintenant                                                                         |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| 16 rôles numérotés qui copient un script bash dans `/tmp` et l'exécutent | Rôles à responsabilité unique, en modules Ansible : relançables sans effet de bord |
| Mots de passe en clair (`admin`, Grafana…), `PasswordAuthentication yes` | Secrets dans **Ansible Vault**, SSH par clés uniquement                            |
| `kubeadm init` seul : `k8s2` et `node1` rejoignaient à la main           | Rôle `kubeadm_join` : control planes supplémentaires + workers automatisés         |
| Versions « latest » (Flannel, MetalLB, ingress-nginx, Helm)              | Toutes les versions épinglées dans `group_vars/all/main.yml`                       |
| Kubernetes 1.31 (fin de support)                                         | Kubernetes 1.36.x, API kubeadm `v1beta4`                                           |
| IP et noms codés en dur dans chaque script                               | Inventaire + variables : `/etc/hosts`, HAProxy, Corosync, certSANs en sont déduits |
| Scripts RBAC / monitoring / metrics-server à lancer à la main            | Rôles `k8s_rbac`, `monitoring`, `metrics_server` pilotés par variables             |

La correspondance fichier par fichier est dans [docs/MIGRATION.md](docs/MIGRATION.md).

## Prérequis

**Poste de contrôle** (Rocky 10 ou autre Linux) :

```bash
sudo dnf install -y ansible-core sshpass          # sshpass : seulement pour l'étape 0 (--ask-pass)
ansible-galaxy collection install -r requirements.yml
```

Le poste de contrôle a aussi besoin du module Python `cryptography` si vous utilisez la création
d'utilisateurs par certificat (`k8s_rbac`).

**Nœuds** : Rocky Linux 10.2 installé, un compte initial avec `sudo`, accès Internet sortant
(dépôts `pkgs.k8s.io`, Docker CE, GitHub, `get.helm.sh`, PyPI) — ou des miroirs internes (voir `k8s_tooling_pip_index_url`,
`containerd_repo_baseurl`).

## Démarrage rapide

```bash
# 1. Adapter l'inventaire et les variables
$EDITOR inventories/production/hosts.yml
$EDITOR inventories/production/group_vars/all/main.yml

# 2. Secrets
cp inventories/production/group_vars/all/vault.yml.example inventories/production/group_vars/all/vault.yml
$EDITOR inventories/production/group_vars/all/vault.yml
ansible-vault encrypt inventories/production/group_vars/all/vault.yml

# 3. Étape 0, une seule fois : compte « ansible » + clé SSH (utilise les comptes initiaux)
ansible-playbook playbooks/00-bootstrap.yml --ask-pass --ask-become-pass

# 4. Déploiement complet
ansible-playbook playbooks/site.yml --ask-vault-pass
```

Par défaut le bootstrap se connecte avec un compte portant **le nom de l'hôte** (comme dans les
anciens scripts). Pour un même compte initial partout : `-e bootstrap_initial_user=admin`.

### Exécuter par étape ou par tag

| Playbook              | Contenu                                                                                                    |
| --------------------- | ---------------------------------------------------------------------------------------------------------- |
| `01-nodes.yml`        | `common`, `firewall`, `k8s_prerequisites`, `containerd`, `kubernetes_packages`                             |
| `02-loadbalancer.yml` | `haproxy`, `pacemaker_cluster`, `loadbalancer_vip`                                                         |
| `03-kubernetes.yml`   | `k8s_tooling`, `kubeadm_init`, `cni_flannel`, `kubeadm_join`, `k8s_post_install`                           |
| `04-addons.yml`       | `metallb`, `nfs_csi`, `ingress_nginx`, `metrics_server`, `monitoring`, `k8s_external_services`, `k8s_rbac` |

```bash
ansible-playbook playbooks/04-addons.yml --tags metallb,ingress_nginx --ask-vault-pass
ansible-playbook playbooks/01-nodes.yml --check --diff --ask-vault-pass     # simulation
```

## Opérations courantes

- **Ajouter un worker / un control plane** : ajouter l'hôte dans `hosts.yml`, puis
  `ansible-playbook playbooks/01-nodes.yml --limit <hôte>` puis `playbooks/03-kubernetes.yml`
  (rôles `kubeadm_join` + `k8s_post_install`). Pour un control plane, mettre à jour HAProxy :
  `ansible-playbook playbooks/02-loadbalancer.yml --tags haproxy`.
- **Désinstaller la supervision** :
  `ansible-playbook playbooks/04-addons.yml --tags monitoring -e monitoring_state=absent`
- **Vérifier les droits RBAC** :
  `ansible-playbook playbooks/04-addons.yml --tags rbac_verify -e k8s_rbac_verify=true`
- **Approuver les nouveaux certificats kubelet** (renouvellement annuel) :
  `ansible-playbook playbooks/03-kubernetes.yml --tags csr`
- Les kubeconfig et certificats des comptes RBAC sont écrits dans `artifacts/rbac/` sur le poste de contrôle
  (ignoré par git, permissions `0600`).

## Structure du dépôt

```
ansible.cfg                       configuration (SSH pipelining, accept-new…)
requirements.yml                  collections Ansible
inventories/production/
  hosts.yml                       hôtes et groupes
  group_vars/all/                 main.yml, firewall.yml, rbac.yml, workloads.yml, secrets.yml, vault.yml(.example)
  group_vars/<groupe>.yml         pare-feu et variables par type de nœud
playbooks/                        00-bootstrap … 04-addons, site.yml
roles/                            20 rôles (voir ci-dessous)
examples/                         manifestes de démonstration
docs/MIGRATION.md                 correspondance ancien → nouveau
```

| Rôle                                                                  | Rôle dans le déploiement                                               |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `common`                                                              | nom d'hôte, paquets, `/etc/hosts`, NTP (chrony), durcissement SSH      |
| `firewall`                                                            | firewalld : ports, services, sources de confiance (définis par groupe) |
| `k8s_prerequisites`                                                   | swap, SELinux, modules noyau, sysctl, paquets réseau                   |
| `containerd`                                                          | dépôt Docker CE (RHEL), `containerd.io`, cgroups systemd               |
| `kubernetes_packages`                                                 | dépôt `pkgs.k8s.io`, kubelet/kubeadm/kubectl à version exacte          |
| `haproxy`                                                             | HAProxy devant l'API (sonde `/livez`), service piloté par Pacemaker    |
| `pacemaker_cluster`                                                   | cluster pcs/Corosync à 2 nœuds                                         |
| `loadbalancer_vip`                                                    | ressources Pacemaker : VIP + HAProxy (groupe)                          |
| `k8s_tooling`                                                         | Helm (somme de contrôle vérifiée), venv Python pour `kubernetes.core`  |
| `kubeadm_init`                                                        | `kubeadm init` depuis un fichier de configuration `v1beta4`            |
| `cni_flannel`                                                         | Flannel, version épinglée, CIDR aligné sur `k8s_pod_cidr`              |
| `kubeadm_join`                                                        | jonction des control planes et workers (jetons éphémères)              |
| `k8s_post_install`                                                    | approbation des CSR kubelet, attente des nœuds Ready, libellés         |
| `metallb`, `ingress_nginx`, `metrics_server`, `monitoring`, `nfs_csi` | addons                                                                 |
| `k8s_rbac`, `k8s_external_services`                                   | comptes/droits, services vers bases externes                           |

## Variables globales

Les variables partagées entre rôles sont définies une seule fois dans
`inventories/production/group_vars/all/main.yml` ; les rôles n'en redéfinissent pas (convention de
nommage `<rôle>_…` pour les variables propres à chaque rôle, avec leurs valeurs par défaut dans `defaults/main.yml`).
Un rôle utilisé seul a donc besoin de : `k8s_version`, `k8s_pod_cidr`, `k8s_service_cidr`, `k8s_control_plane_vip`,
`k8s_control_plane_port`, `k8s_control_plane_endpoint`, `k8s_api_hostname`, `k8s_kube_proxy_mode`, `k8s_selinux_state`.

## Points d'attention avant la production

1. **etcd à 2 membres ne tolère aucune panne.** Avec 2 control planes, la perte d'un nœud fait perdre le
   quorum etcd. Passez à **3 control planes** (décommenter `k8s3` dans l'inventaire) : le rôle gère N nœuds.
2. **ingress-nginx est retiré par le projet Kubernetes depuis mars 2026** : plus aucun correctif de sécurité
   ([annonce](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)). Le rôle le conserve pour reproduire
   l'installation existante (désactivable avec `ingress_nginx_enabled: false`) ; planifiez la migration vers
   Gateway API ou un autre contrôleur.
3. **Secrets compromis** : les mots de passe qui figuraient dans l'ancien dépôt public (`admin`, mot de passe Grafana,
   secrets de bases de données encodés en base64) doivent être changés ; ils restent visibles dans l'historique git.
4. **Adresses IP** : les anciens scripts étaient incohérents sur `k8s1`/`k8s2` (`.97` ou `.98`). L'inventaire retient
   `k8s1 = .98`, `k8s2 = .97` (valeurs de HAProxy et `/etc/hosts`) : **vérifiez-les**.
5. **Pacemaker sans STONITH** (`pacemaker_stonith_enabled: false`) : acceptable pour une VIP + HAProxy sans état,
   mais un cluster à 2 nœuds sans fencing reste exposé au split-brain.
6. **SELinux en `permissive`** (recommandation de la documentation kubeadm). Passer en `enforcing` demande de tester
   vos workloads (`k8s_selinux_state`).
7. **Certificats kubelet** (`serverTLSBootstrap`) : permet à metrics-server de fonctionner sans `--kubelet-insecure-tls`,
   mais les CSR sont approuvées automatiquement par `k8s_post_install`. C'est acceptable à l'ajout d'un nœud par
   l'administrateur ; elles se renouvellent chaque année et doivent être ré-approuvées (tag `csr`).
8. **Métriques exposées** : `k8s_expose_control_plane_metrics: true` fait écouter etcd (2381), le scheduler, le
   controller-manager et kube-proxy sur toutes les interfaces des control planes pour Prometheus. Le pare-feu limite
   l'accès ; désactivez l'option si vous n'utilisez pas le monitoring.
9. **Sauvegardes etcd** : non incluses. À ajouter (snapshot régulier + stockage externe) avant la mise en production.
10. **Mise à jour du cluster** : ce dépôt installe ; les montées de version (`kubeadm upgrade`) restent à outiller.

## Limites de la vérification

Cette réécriture a été validée par **analyse statique** : parsing YAML de tous les fichiers et rendu des templates
(HAProxy, kubeadm init/join, values Prometheus, kubeconfig) avec les variables de l'inventaire. Elle n'a **pas été
exécutée sur des machines Rocky Linux 10.2** : faites un premier passage en `--check --diff` puis sur un environnement
de test avant la production. Lancez aussi `make lint` (ansible-lint, yamllint) — la CI GitHub (`.github/workflows/lint.yml`)
le fait à chaque push.
