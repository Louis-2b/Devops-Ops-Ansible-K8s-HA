# Migration : ancien dépôt (scripts bash) → rôles Ansible

## Correspondance des fichiers

| Ancien fichier                                              | Nouveau emplacement                                                     | Remarques                                                                                                           |
| ----------------------------------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `install_ansible.sh`                                        | `README.md` (prérequis), `ansible.cfg`, `playbooks/00-bootstrap.yml`    | Plus de configuration générée par script ; la clé SSH est créée par `openssh_keypair` (non écrasée)                 |
| `copy_pub_key.sh`                                           | `playbooks/00-bootstrap.yml`                                            | `authorized_key` + sudoers au lieu de `sshpass`/`ssh-copy-id` ; mot de passe demandé par `--ask-pass`               |
| `HA_k8s_cluster.yml`                                        | `playbooks/site.yml` et `playbooks/01…04`                               | Une play par étape, hôtes ciblés par groupes plutôt que par `when: inventory_hostname == …`                         |
| `roles/01-k8s1_ssh_keys`, `02-haproxy1_ssh_keys`            | _supprimés_                                                             | Servaient aux `scp`/`ssh` entre nœuds dans les scripts ; Ansible distribue désormais les fichiers lui-même          |
| `roles/03/04/05-config_firewall_*`                          | `roles/firewall` + `group_vars/*`                                       | Un seul rôle, ports définis par groupe. Ports corrigés (voir ci-dessous)                                            |
| `roles/06-k8s_prereq`                                       | `roles/k8s_prerequisites`                                               | `selinux`, `modprobe`, `sysctl`, `replace` ; IPVS seulement si `k8s_kube_proxy_mode: ipvs`                          |
| `roles/07-system_config`                                    | `roles/common`                                                          | `/etc/hosts` géré par `blockinfile` (l'ancien script ajoutait les lignes à chaque exécution)                        |
| `roles/08-install_containerd`                               | `roles/containerd`                                                      | Dépôt `rhel/<version>` au lieu de `centos`, config régénérée de façon déterministe                                  |
| `roles/09-install_k8s_tools`                                | `roles/kubernetes_packages`                                             | Versions exactes, `disable_excludes`                                                                                |
| `roles/10-config_haproxy`                                   | `roles/haproxy`                                                         | Sonde `/livez` en HTTPS (l'ancienne combinait `httpchk` et `ssl-hello-chk`), service désactivé (géré par Pacemaker) |
| `roles/11-install_ha_tools`, `12-config_corosync-pacemaker` | `roles/pacemaker_cluster`                                               | `pcs host auth` + `pcs cluster setup` au lieu d'un `corosync.conf` écrit à la main et copié par `scp`               |
| `roles/13-config_kube-vip`                                  | `roles/loadbalancer_vip`                                                | Ce rôle ne faisait pas du kube-vip : il créait la VIP Pacemaker + la ressource HAProxy                              |
| `roles/14-init_k8s_cluster`                                 | `roles/kubeadm_init`, `cni_flannel`, `kubeadm_join`, `k8s_post_install` | Configuration `v1beta4`, Flannel épinglé, jonction des nœuds automatisée                                            |
| `roles/15-install_ingress-nginx`                            | `roles/ingress_nginx`                                                   | Chart Helm épinglé au lieu de l'archive « latest » (voir avertissement de retrait)                                  |
| `roles/16-install-MetalLB`                                  | `roles/metallb`                                                         | Manifeste épinglé ; l'attente du webhook remplace la modification `failurePolicy: Ignore`                           |
| `metrics-server/*`                                          | `roles/metrics_server`                                                  | Chart Helm ; `enable-aggregator-routing` passe dans la config `kubeadm`                                             |
| `monitoring/setup-monitoring.sh`                            | `roles/monitoring` (`install.yml`)                                      | Mêmes valeurs ; identifiants Grafana depuis le vault, plus de fichier `values.yaml` laissé sur le nœud              |
| `monitoring/uninstall-prometheus.sh`                        | `roles/monitoring` (`uninstall.yml`)                                    | `-e monitoring_state=absent`                                                                                        |
| `monitoring/check-monitoring.sh`                            | `roles/monitoring` (`install.yml`, tâches taguées `verify`)             | Le mot de passe n'est plus affiché                                                                                  |
| `rbac/*.sh`                                                 | `roles/k8s_rbac` + `group_vars/all/rbac.yml`                            | Comptes décrits en variables ; vérifications dans `verify.yml`                                                      |
| `database/*.yaml`                                           | `roles/k8s_external_services` + `group_vars/all/workloads.yml`          | `EndpointSlice` (l'API `Endpoints` est dépréciée) ; **secrets retirés du dépôt**                                    |
| `pilote-nfs/*.yaml`                                         | `roles/nfs_csi` (StorageClass) + `examples/nfs-demo/`                   | Le pilote CSI NFS est maintenant installé par le rôle                                                               |
| `ingress/ingress.yaml`                                      | `examples/ingress-demo/`                                                | Démo                                                                                                                |

## Corrections de comportement

- **Pare-feu control plane** : ports `10251`/`10252` (obsolètes) remplacés par `10257` (controller-manager) et
  `10259` (scheduler) ; ajout de `8472/udp` (VXLAN Flannel), `7946` (MetalLB) et des CIDR pods/services en zone de confiance.
- **HAProxy** : l'ancien script activait `haproxy` dans systemd _et_ le déclarait dans Pacemaker ; il n'est plus
  démarré qu'à travers Pacemaker.
- **Resources Pacemaker** : `colocation` + `order` remplacés par un groupe `lb_group` (même sémantique).
- **SSH** : `PasswordAuthentication` n'est plus activé ; l'ancien script le forçait à `yes`.
- **Mise à jour système** : `dnf update` n'est plus lancé dans plusieurs rôles (option `common_upgrade_packages`).

## Reprise d'un cluster déjà déployé avec les anciens scripts

Les rôles sont idempotents, mais ne cherchent pas à adopter un cluster existant : `kubeadm_init` ne
s'exécute pas si `/etc/kubernetes/admin.conf` existe, ce qui est le comportement voulu. Avant de relancer
`site.yml` sur un cluster en service : exécuter d'abord en `--check --diff`, et noter que `containerd` et HAProxy
verront leur configuration régénérée (une sauvegarde `.bak` datée est créée à chaque modification).
