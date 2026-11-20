# HTTPS avec cert-manager - P3 / Follow-up 1

## Etat et fonctionnement

Organisation : `base/` pour les valeurs Helm communes, `local/` pour les tests
auto-signes et `aws/` pour les issuers ACME et les exemples publics.
Voir la [structure P3](../STRUCTURE-P3.md).

Installation et parcours HTTPS auto-signe testes en local le 18 novembre 2026,
avec succes. Aucun deploiement AWS ni certificat Let's Encrypt obtenu a ce stade.
Le cluster local a ete arrete apres verification pour limiter sa consommation.
Voir le [compte rendu du test local](local/RESULTATS.md).

cert-manager obtient et renouvelle les certificats ; Traefik sert HTTPS avec
la cle et le certificat stockes dans un Secret TLS du namespace de l'application.
Nous reutilisons le chart officiel **jetstack/cert-manager v1.21.3**, sans creer
de chart maison. Les CRD sont installees par Helm et conservees a la desinstallation.
Les budgets CPU/RAM sont des points de depart a ajuster selon les mesures.

Trois situations sont separees :

| Environnement | Emetteur | Reconnu par le navigateur |
| --- | --- | --- |
| Local k3d | Issuer auto-signe | Non, avertissement attendu |
| AWS, essais | Let's Encrypt staging | Non, avertissement attendu |
| AWS, validation finale | Let's Encrypt production | Oui si le domaine, la chaine et les dates sont corrects |

## 1. Prerequis

- Confirmer avec P1 le contexte kubectl, la version Kubernetes et la compatibilite
  de cette version de cert-manager. Le chart declare Kubernetes >= 1.22 ; cela
  ne remplace pas la verification de sa matrice de support.
- Traefik et whoami deja deployes selon le [guide Ingress](../ingress/DEPLOIEMENT.md).
- Sur AWS : DNS test.3.120.212.20.sslip.io vers l'IP elastique confirmee de kube-1,
  port public 80 -> NodePort 30080 et 443 -> 30443. Une resolution DNS seule ne suffit pas.
- Les pods solveurs doivent etre joignables par Traefik et le controleur doit
  pouvoir verifier l'URL publique HTTP-01. Verifier DNS, egress et NetworkPolicies.
- Une seule installation cert-manager pour le cluster ; verifier `helm list -A`.

Les solveurs HTTP-01 creent leurs pods dans le namespace du Certificate. Les
politiques P4 actuelles ciblent `kubequest-app` et imposent notamment le registry
prive et certains labels : coordonner avec P4 l'image miroir du solveur et son
podTemplate avant les certificats Laravel. Ne pas desactiver les politiques
globalement. Le premier test utilise `ingress-test`, hors de ce perimetre.

## 2. Installation Helm

Depuis la racine du depot, dans un terminal configure pour le cluster cible :

```bash
kubectl config current-context
helm list -A
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager --version v1.21.3 --namespace cert-manager --create-namespace -f infrastructure/cert-manager/base/values.yaml --wait --timeout 5m
kubectl get pods -n cert-manager
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s
```

Pour k3d, utiliser le kubeconfig separe obtenu avec `k3d kubeconfig write kubequest-p3`
et ajouter `--kubeconfig <chemin>` aux commandes Helm et kubectl, comme dans le
[guide local](../ingress/local/README.md). Ne pas redemarrer Docker sans en avoir besoin.

## 3. Verification locale (sans Let's Encrypt)

Quand le cluster k3d, Traefik et whoami sont redemarres, puis cert-manager installe :

```bash
kubectl apply -f infrastructure/cert-manager/local/test-https.yaml
kubectl wait --for=condition=Ready certificate/ingress-test-local-tls -n ingress-test --timeout=120s
```

Depuis PowerShell sur le PC :

```powershell
curl.exe --noproxy "*" -k -i https://test.127.0.0.1.sslip.io:8443/
curl.exe --noproxy "*" -k -i https://app.127.0.0.1.sslip.io:8443/
```

Attendu : HTTP 200, reponse whoami. `-k` desactive uniquement pour ce test la
verification du certificat auto-signe. Sans `-k`, une erreur de confiance est
attendue. Ne pas importer ce certificat dans les autorites de confiance du PC.
Ce test ne valide pas le critere de certificat public reconnu.

## 4. AWS : obtenir d'abord un certificat staging

L'adresse email ACME est facultative et n'est pas inventee dans les manifests.
L'equipe peut renseigner `spec.acme.email` dans les deux ClusterIssuers avant
application. Les cles de compte sont generees par cert-manager dans son namespace ;
ne jamais exporter les Secrets ou les commiter.

```bash
kubectl apply -f infrastructure/cert-manager/aws/issuers/letsencrypt-staging.yaml
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-staging --timeout=120s
kubectl apply -k infrastructure/cert-manager/aws/staging
kubectl wait --for=condition=Ready certificate/ingress-test-tls -n ingress-test --timeout=300s
kubectl get certificate,certificaterequest,order,challenge -n ingress-test
```

Le Certificate nomme explicitement le Secret TLS ; l'Ingress HTTPS l'utilise sur
`websecure`. Il n'y a pas d'annotation ingress-shim : un seul Certificate gere ce
Secret. La route HTTP existante reste disponible pour ce premier jalon.

Tester `https://test.3.120.212.20.sslip.io` : l'avertissement de confiance staging
est normal. On peut utiliser `curl -k -i` pour ce diagnostic uniquement.
HTTP-01 valide chaque nom individuellement, sans wildcard ni serveur DNS a installer.

## 5. AWS : passer en production

Uniquement apres succes du staging :

```bash
kubectl apply -f infrastructure/cert-manager/aws/issuers/letsencrypt-production.yaml
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-production --timeout=120s
kubectl apply -k infrastructure/cert-manager/aws/production
kubectl get certificate ingress-test-tls -n ingress-test -w
```

Attendre la nouvelle emission : verifier la revision du Certificate, son evenement
d'emission et son issuerRef production. Un ancien Ready=True juste apres le changement
ne suffit pas a prouver que le certificat staging a deja ete remplace. Ne plus
reappliquer `aws/staging` ensuite, car cela remettrait le Certificate sur staging.

Depuis un PC hors AWS, **sans `-k`** :

```powershell
curl.exe -i --connect-timeout 10 --max-time 20 https://test.3.120.212.20.sslip.io/
```

Attendu : HTTP 200 et verification TLS reussie. Dans le navigateur, inspecter la
securite de la connexion : certificat reconnu, bon nom DNS et dates valides.
L'icone depend du navigateur ; aucune exception manuelle ne doit etre necessaire.

## 6. Etendre a Laravel et aux outils

Chaque service expose doit disposer d'un Ingress TLS et d'un certificat couvrant
son propre nom : app, argocd, keycloak, dex, grafana, headlamp, etc. Le test whoami
seul ne termine pas la migration de tous les acces en HTTPS.

Avec P2 : conserver l'Ingress Laravel dans `kubequest-app`, ajouter une section
`spec.tls` avec le nom `app.3.120.212.20.sslip.io` et un Secret de ce namespace.
Utiliser soit un Certificate explicite avec issuerRef `letsencrypt-production`,
soit l'annotation `cert-manager.io/cluster-issuer: letsencrypt-production` pour
ingress-shim, mais pas les deux pour le meme Secret. Configurer la route Traefik
sur `websecure` avec TLS et mettre l'URL Laravel en HTTPS (proxies de confiance a
verifier avec P2). Retirer la route temporaire `app` avant de l'activer.

La redirection HTTP -> HTTPS est une etape a coordonner une fois les certificats
valides. Conserver le port 80 et verifier que la route `/.well-known/acme-challenge/`
reste accessible pour les renouvellements ; ne pas rediriger les solveurs vers
une authentification OIDC. Les fichiers ici n'ajoutent pas encore de redirection.

## Diagnostic et preuves

```bash
kubectl describe certificate ingress-test-tls -n ingress-test
kubectl get certificaterequest,order,challenge -n ingress-test
kubectl describe challenge -n ingress-test
kubectl logs deployment/cert-manager -n cert-manager --tail=100
```

En cas de challenge bloque : verifier l'acces Internet sur 80, le host, la classe
`traefik`, les pods solveurs, le DNS vu du cluster et les refus d'admission.
En cas de certificat Traefik par defaut : verifier le Secret TLS et le namespace.
Ne pas supprimer/recreer sans cesse les Certificates en production (limites ACME).
cert-manager renouvelle les certificats automatiquement : surveiller Ready,
expiration et renouvellement, et conserver les Secrets lors des redemarrages.

- [ ] cert-manager installe dans le cluster cible.
- [ ] Certificat Let's Encrypt production emis pour les services exposes.
- [ ] HTTPS reconnu par le navigateur sans exception, pour chaque service expose.

Conserver date, sorties de verification sans secrets et captures du navigateur.

## GitOps et nettoyage

Les fichiers d'amorcage ArgoCD du depot sont actuellement vides. Avec P1, integrer
une seule release Helm cert-manager et ses CRD, puis appliquer les issuers et
Certificates une fois le webhook disponible. Exclure les manifests locaux du
perimetre AWS et choisir staging OU production pour whoami. Ne pas faire un
`kubectl apply -R` sur tout ce dossier. Les Secrets de comptes ACME et TLS sont
generes dans le cluster, pas dans Git.

Le nettoyage de whoami supprime son namespace et donc ses Certificates/Secrets.
Retirer aussi les Ingress HTTPS de test si necessaire. Ne pas desinstaller
cert-manager : les autres services en dependent. Les CRD conservees par Helm ne
doivent pas etre supprimees sans evaluer les certificats de tout le cluster.

References : [Helm officiel](https://cert-manager.io/docs/installation/helm/),
[HTTP-01](https://cert-manager.io/docs/configuration/acme/http01/),
[support Kubernetes](https://cert-manager.io/docs/releases/).
