# Keycloak local sur k3d

Cette variante reprend `../base`, change le hostname en
`https://keycloak.127.0.0.1.sslip.io:8443`, utilise le stockage `local-path` de
k3d et un certificat auto-signe fourni par cert-manager. Aucun issuer ACME ni
adresse AWS n'est utilise. Le PVC PostgreSQL fait 1Gi.

## Prerequis et installation

Docker Desktop et le cluster `kubequest-p3` doivent etre demarres, avec Traefik
et cert-manager installes selon leurs guides. Utiliser uniquement le kubeconfig
local separe. Depuis PowerShell, a la racine du depot :

```powershell
& "$env:TEMP/kubequest-ingress-tools/k3d.exe" cluster start kubequest-p3
$p3Kubeconfig = & "$env:TEMP/kubequest-ingress-tools/k3d.exe" kubeconfig write kubequest-p3
kubectl --kubeconfig $p3Kubeconfig get nodes
kubectl --kubeconfig $p3Kubeconfig apply -f infrastructure/auth/keycloak/base/namespace.yaml
```

Creer les Secrets `keycloak-db` et `keycloak-bootstrap` s'ils n'existent pas,
avec le script interactif `../create-secrets.sh` depuis un terminal Bash dont
le KUBECONFIG cible ce meme cluster local. Voir le [guide commun](../README.md).
Ne pas reutiliser les mots de passe AWS dans le cluster de test.

Puis, dans PowerShell :

```powershell
kubectl --kubeconfig $p3Kubeconfig apply -k infrastructure/auth/keycloak/local
kubectl --kubeconfig $p3Kubeconfig rollout status statefulset/keycloak-db -n auth --timeout=300s
kubectl --kubeconfig $p3Kubeconfig rollout status deployment/keycloak -n auth --timeout=600s
kubectl --kubeconfig $p3Kubeconfig wait --for=condition=Ready certificate/keycloak-local-tls -n auth --timeout=120s
curl.exe --noproxy "*" -k -i https://keycloak.127.0.0.1.sslip.io:8443/realms/kubequest/.well-known/openid-configuration
```

Attendu : HTTP 200 et issuer contenant le nom local avec le port 8443.
L'avertissement navigateur est normal pour ce certificat auto-signe : ce test ne
valide pas Let's Encrypt. Ne pas installer de certificat local comme autorite
de confiance globale sur le PC.

## Console et comptes

Ouvrir `https://keycloak.127.0.0.1.sslip.io:8443/admin/`. L'administrateur initial
est celui du Secret `keycloak-bootstrap`. Les identifiants restent dans le cluster,
pas dans la documentation ou Git. Pour un test cree avec le script commun,
utiliser le mot de passe saisi lors de son execution.

Dans le realm kubequest, creer les utilisateurs de demonstration et les affecter
aux groupes selon le guide commun. Tester la connexion dans une fenetre privee :
`https://keycloak.127.0.0.1.sslip.io:8443/realms/kubequest/account/`.

Les groupes ne conferent pas encore de droits Kubernetes : Dex et RBAC sont
hors de ce test. La base doit conserver les utilisateurs lors du remplacement
du pod PostgreSQL. Ne pas supprimer auth ou son PVC pour tester un redemarrage.

Les Secrets generes pendant une verification automatisee peuvent inclure
`keycloak-local-test-users`, qui conserve uniquement les mots de passe des comptes
de demonstration locaux. Ne pas publier leur contenu. Les eventuels clients OIDC
temporaires de verification doivent etre retires apres le test.
