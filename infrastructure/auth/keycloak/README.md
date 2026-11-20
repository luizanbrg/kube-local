# Identity provider : Keycloak - P3 / Follow-up 1

Pour tester sans AWS, voir le [guide local k3d](local/README.md).

## Etat et choix justifie

Configuration deployee et testee sur k3d le 18 novembre 2026 : Keycloak,
PostgreSQL, HTTPS auto-signe, deux comptes et persistance valides localement.
Voir les [resultats locaux](local/RESULTATS.md). Aucun deploiement AWS ni
certificat public reconnu valide a ce stade. Le cluster est arrete apres test.

Keycloak est un fournisseur d'identite open source : il gere utilisateurs,
groupes et clients OIDC avec une console d'administration. Il repond au besoin
d'un annuaire heberge par l'equipe dans le cluster, et pourra etre relie a Dex
au Follow-up 2. Keycloak stocke ses donnees dans une base PostgreSQL dediee :
les utilisateurs ne dependent ni du disque d'un pod ni de la base Laravel de P2.

Nous utilisons des manifests Kubernetes/Kustomize et les images officielles,
sans chart Helm tiers supplementaire. Le sujet impose un chart pour Laravel,
pas pour chaque composant d'infrastructure. Ce choix laisse visibles le stockage,
les Secrets et la configuration proxy pour ce petit deploiement mono-instance.
Une integration GitOps avec P1 reste a faire.

Versions epinglees : Keycloak 26.8.2, PostgreSQL 17.7-bookworm, toutes deux
disponibles en linux/arm64 et linux/amd64 (index des images verifies).
Verifier les mises a jour de securite avant deploiement et maintenir ces versions.
Keycloak tourne avec `start`, pas `start-dev`. Le cache local et un seul replica
sont choisis pour le laboratoire ; ce n'est pas une configuration haute disponibilite.
Le demarrage realise la construction Keycloak a la volee ; une image optimisee
pourra etre construite plus tard pour accelerer ce demarrage.

## Architecture et fichiers

```text
Navigateur HTTPS -> kube-1:443 -> Traefik -> Service keycloak:80
  -> Keycloak:8080 -> Service keycloak-db:5432 -> PostgreSQL + PVC
```

Le TLS se termine sur Traefik. La liaison interne Traefik -> Keycloak est HTTP,
restreinte par NetworkPolicy aux pods Traefik du namespace ingress. Le port de
sante 9000 n'est ni expose par le Service ni route par l'Ingress. Calico doit
appliquer les NetworkPolicies ; les probes du kubelet restent autorisees.
Traefik doit ecraser les en-tetes X-Forwarded-* et ne pas faire confiance aux
en-tetes envoyes par des clients arbitraires.

| Fichier/dossier | Role |
| --- | --- |
| `base/` | Namespace auth, PostgreSQL, Keycloak, realm sans secrets et regles reseau |
| `aws/` | Base + Ingress HTTPS avec cert-manager |
| `create-secrets.sh` | Creation interactive des Secrets de bootstrap, sans mot de passe dans Git |

Le realm `kubequest` et les groupes `kubequest-admins` / `kubequest-readers` sont
importes au premier demarrage. Aucun utilisateur ni mot de passe n'est dans le JSON.
Si le realm existe deja, l'import de demarrage ne le met pas a jour : modifier
ensuite avec la console ou une future automatisation admin, pas en supprimant la base.
Ces groupes n'accordent aucun droit Kubernetes tant que Dex/RBAC ne sont pas configures.

## Prerequis avec P1/P3

- Cluster pret, contexte kubectl verifie, images accessibles depuis les noeuds.
- Traefik, acces public 80/443 et cert-manager deja valides ; ClusterIssuer
  `letsencrypt-production` Ready. Faire les essais staging de cert-manager d'abord.
- Nom `keycloak.3.120.212.20.sslip.io` vers l'IP elastique confirmee de kube-1.
- Stockage persistant provisionne avec P1 : le StatefulSet demande un PVC
  `data-keycloak-db-0` de 1Gi dans auth. Aucune StorageClass n'est inventee ici.

**Stockage a fixer avant installation** : avec une StorageClass par defaut, le
PVC l'utilisera. Sinon, fournir un PV compatible pre-lie a ce claim ou ajouter
la StorageClass convenue dans `volumeClaimTemplates`. Sur AWS, coordonner avec
P1 un stockage EFS dans un repertoire dedie et correctement prepare. Le repertoire
PostgreSQL doit appartenir a UID/GID 999, avec droits 0700 ; `fsGroup` seul peut
ne pas suffire sur NFS/EFS. Ne pas partager ce repertoire avec MySQL ou un second
PostgreSQL. Verifier les contraintes de montage et la durabilite des ecritures
avec P1. Aucun pod root de changement de droits n'est ajoute automatiquement.

Requests cumulees Keycloak + DB : 350m CPU et 640Mi RAM ; limites : 1,5 CPU et
2Gi RAM. A confronter au budget du cluster avec monitoring, Laravel et les autres
composants. Les donnees restent sur le PVC apres remplacement des pods ; cela
ne constitue pas une sauvegarde. Prevoir sauvegarde et restauration avant usage durable.

## Installation AWS (shell Bash configure pour le cluster)

Depuis la racine du depot :

```bash
kubectl config current-context
kubectl get nodes
kubectl get storageclass
kubectl get clusterissuer letsencrypt-production

kubectl apply -f infrastructure/auth/keycloak/base/namespace.yaml
bash infrastructure/auth/keycloak/create-secrets.sh
kubectl kustomize infrastructure/auth/keycloak/aws
kubectl apply -k infrastructure/auth/keycloak/aws
kubectl get pvc,pods -n auth
kubectl rollout status statefulset/keycloak-db -n auth --timeout=300s
kubectl rollout status deployment/keycloak -n auth --timeout=600s
kubectl get ingress,certificate -n auth
kubectl wait --for=condition=Ready certificate/keycloak-tls -n auth --timeout=300s
```

Le script demande deux mots de passe distincts, sans echo, et refuse d'ecraser les
Secrets existants. Il faut verifier le contexte avant son execution. En cas de
creation partielle, gerer le Secret manquant explicitement, sans supprimer la DB.
Changer le Secret PostgreSQL apres initialisation ne change pas automatiquement
le mot de passe dans la base : toute rotation doit etre coordonnee.

Pour le GitOps, remplacer ce bootstrap manuel par des SealedSecrets chiffres pour
le cluster cible avec P1. Ne pas commiter de Secret Kubernetes encode en base64,
de kubeconfig, d'export du realm contenant des credentials ni de fichier temporaire.
Le certificat et sa cle TLS sont generes par cert-manager dans auth.

## Creer les utilisateurs de test

1. Ouvrir `https://keycloak.3.120.212.20.sslip.io/admin/` et verifier la connexion
   TLS sans avertissement. Se connecter avec `bootstrap-admin` et le mot de passe
   choisi dans le script.
2. Selectionner le realm **kubequest**, pas master. Verifier les deux groupes.
3. Dans **Users**, creer `bastian-admin` et `bastian-reader`, activer les comptes.
   Dans **Credentials**, definir pour chacun un mot de passe distinct, temporaire
   si vous voulez imposer un changement a la premiere connexion.
4. Dans **Groups**, rattacher `bastian-admin` a `kubequest-admins`, et
   `bastian-reader` a `kubequest-readers`.
5. Dans une fenetre privee, ouvrir
   `https://keycloak.3.120.212.20.sslip.io/realms/kubequest/account/`, se connecter
   avec chaque compte et verifier l'acces. Aucun role d'administration de Keycloak
   n'est donne a ces comptes par leur simple appartenance aux groupes.
6. Creer un administrateur permanent dans **master**, lui attribuer le role de
   realm `admin` pour administrer cette instance, verifier son acces dans
   une autre session, puis supprimer le compte temporaire bootstrap-admin.
   Retirer ensuite les variables `KC_BOOTSTRAP_ADMIN_*` du Deployment et le Secret
   de bootstrap lors d'une modification coordonnee du depot. Garder un acces admin
   fonctionnel avant de retirer le bootstrap.

Ne pas diffuser les mots de passe dans Trello, les captures ou Git. Les comptes
permanents de gestion de l'annuaire sont distincts des utilisateurs de demonstration.

## Verifications et Definition of Done

Depuis PowerShell sur le PC hors AWS :

```powershell
Resolve-DnsName keycloak.3.120.212.20.sslip.io -Type A
curl.exe -i --connect-timeout 10 --max-time 20 https://keycloak.3.120.212.20.sslip.io/realms/kubequest/.well-known/openid-configuration
```

Attendu : HTTP 200 sans `-k`, document OIDC avec issuer
`https://keycloak.3.120.212.20.sslip.io/realms/kubequest`.
Verifier aussi la console et les connexions des deux comptes. Enfin, redemarrer
les pods lors d'un test planifie et constater que le realm et les comptes persistent.

- [x] Choix Keycloak justifie dans ce document.
- [ ] Keycloak deploye et accessible en HTTPS avec certificat reconnu.
- [ ] Deux utilisateurs de test crees et connexions verifiees.

Conserver dates, captures sans secrets et sorties de verification pour Trello.
Ne pas cocher l'accessibilite sur la seule base du rendu Kustomize.

## Diagnostic et suite

```bash
kubectl get pods,pvc,svc,ingress,certificate -n auth
kubectl describe pvc data-keycloak-db-0 -n auth
kubectl logs statefulset/keycloak-db -n auth --tail=80
kubectl logs deployment/keycloak -n auth --tail=80
kubectl describe certificate keycloak-tls -n auth
```

PVC Pending : revoir stockage avec P1. PostgreSQL Permission denied : verifier les
droits du volume. Keycloak redemarre : verifier connexion DB, mot de passe et RAM.
Console avec redirections HTTP ou erreurs d'origine : verifier hostname HTTPS,
en-tetes proxy et absence d'acces direct contournant Traefik.
Ne pas supprimer auth ni le PVC pour corriger un probleme de demarrage.

Au Follow-up 2 : deploiement Dex dans auth, client OIDC Keycloak pour Dex, mapper
les groupes et connecter les outils/l'API Kubernetes. Ces integrations ne sont
pas realisees par ce jalon. Keycloak est ici l'annuaire, pas encore le SSO complet.

References : [conteneur officiel](https://www.keycloak.org/server/containers),
[proxy](https://www.keycloak.org/server/reverseproxy),
[base de donnees](https://www.keycloak.org/server/db),
[health checks](https://www.keycloak.org/server/health),
[release 26.8.2](https://www.keycloak.org/2026/11/keycloak-2682-released).
