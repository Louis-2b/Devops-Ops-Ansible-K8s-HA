# Exemples

Manifestes de démonstration, **non appliqués par les playbooks**. Ils servent à valider
rapidement le cluster après déploiement.

| Dossier         | Contenu                                                        | Prérequis                                                                           |
| --------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `ingress-demo/` | Ingress de test (`nginx.local/my-app`)                         | rôle `ingress_nginx` + un service `nginx-service`                                   |
| `nfs-demo/`     | PVC `pvc-nfs-dynamic` + Deployment qui écrit sur le volume NFS | `nfs_csi_enabled: true` (la StorageClass `nfs-csi` est créée par le rôle `nfs_csi`) |

```bash
kubectl apply -f examples/nfs-demo/
kubectl logs deploy/nginx-nfs   # vérifier les écritures
```
