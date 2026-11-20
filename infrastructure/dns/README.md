# DNS public - Follow-up 1 (P3)

La route temporaire publique est dans `aws/app-test-ingress.yaml`. Les noms
locaux sont geres par `../ingress/local/test-ingress.yaml` ; aucun serveur DNS
n'est a deployer. Voir la [structure P3](../STRUCTURE-P3.md).

## Principe et choix

Nous retenons **sslip.io** et la convention `<service>.3.120.212.20.sslip.io`.
Le service DNS public extrait l'IPv4 du nom et la renvoie. Aucun domaine a acheter,
aucune zone Route 53 a creer et aucun serveur DNS a installer dans le cluster.
Reference : [documentation officielle sslip.io / nip.io](https://sslip.io/).

`3.120.212.20` est l'IP elastique de kube-1 communiquee pour le groupe 33 ; la
confirmer dans AWS avant deployment. Ne pas utiliser les IP publiques variables
des workers. Si l'IP elastique change, il faut modifier les noms dans les manifests,
la documentation et, ensuite, les certificats et URLs de retour OIDC.

Le DNS donne uniquement une adresse IP. Traefik choisit ensuite le Service via
le nom Host de la requete. Une resolution DNS correcte ne prouve ni que le port
80 est accessible ni que le service est deploye. Le nom sslip.io ne fournit pas
automatiquement HTTPS : cert-manager fera l'objet de l'issue suivante.

## Convention a partager a l'equipe

Noms en minuscules, un prefixe explicite par service, meme suffixe pour tous.
Ces noms sont reserves par convention ; cette liste ne cree pas de routes.

| Usage | Nom public | Namespace cible | Responsable |
| --- | --- | --- | --- |
| Application Laravel | `app.3.120.212.20.sslip.io` | `kubequest-app` | P2 / P3 |
| Test Ingress | `test.3.120.212.20.sslip.io` | `ingress-test` | P3 |
| ArgoCD | `argocd.3.120.212.20.sslip.io` | `argocd` | P1 / P3 |
| Keycloak | `keycloak.3.120.212.20.sslip.io` | `auth` | P3 |
| Dex | `dex.3.120.212.20.sslip.io` | `auth` | P3 |
| Grafana | `grafana.3.120.212.20.sslip.io` | `monitoring` | P4 / P3 |
| Headlamp | `headlamp.3.120.212.20.sslip.io` | `headlamp` | A attribuer / P3 |

MySQL reste interne, sans nom public ni Ingress. Prometheus et Loki ne sont pas
exposes publiquement par cette convention. Traefik n'a pas besoin de nom public
propre et son dashboard reste desactive.

Pour le premier test, utiliser HTTP. Les services exposes passeront en HTTPS apres
configuration de cert-manager. Le nom d'hote restera identique.

## Validation DNS depuis le PC (possible avant le cluster)

Dans PowerShell :

```powershell
Resolve-DnsName app.3.120.212.20.sslip.io -Type A
Resolve-DnsName test.3.120.212.20.sslip.io -Type A
```

Attendu : un enregistrement A vers `3.120.212.20`, meme si les VM sont arretees.
Si la resolution echoue, comparer avec un autre resolveur autorise sur le reseau
et verifier les filtres DNS locaux avant de modifier le cluster.

## Validation HTTP quand l'Ingress sera deploye

Prerequis : suivre [`../ingress/README.md`](../ingress/README.md), avec l'app whoami
operationnelle et le port public 80 de kube-1 raccorde au NodePort 30080.

Pour tester exactement le nom `app.<IP>.sslip.io` avant que Laravel soit pret,
ce dossier fournit une route **temporaire** vers whoami. Depuis la racine du depot :

```bash
kubectl apply -f infrastructure/dns/aws/app-test-ingress.yaml
kubectl get ingress app-dns-test -n ingress-test
```

Depuis le PC hors AWS, sans port-forward et sans option `--resolve` :

```powershell
curl.exe -i --connect-timeout 10 --max-time 20 http://app.3.120.212.20.sslip.io/
```

Ouvrir egalement cette URL dans le navigateur. Attendu : HTTP 200 avec `Hostname:`
dans la reponse whoami. Cela valide la chaine DNS -> IP publique -> Traefik -> Service.
Un test avec `--resolve` contourne le DNS et ne suffit donc pas a valider cette issue.

### Passage a Laravel avec P2

La route temporaire et le futur Ingress Laravel ne doivent pas utiliser le meme
nom et chemin en parallele. Avant que P2 active sa route `app` :

```bash
kubectl delete -f infrastructure/dns/aws/app-test-ingress.yaml
```

P2 cree ensuite l'Ingress `app.3.120.212.20.sslip.io` dans `kubequest-app`, avec
`ingressClassName: traefik`, vers son propre Service. Aucun changement DNS necessaire.
Refaire le test HTTP, cette fois avec la page Laravel attendue.

## Definition of Done et preuves

- [ ] URL `app.3.120.212.20.sslip.io` fonctionnelle depuis l'exterieur.
- [ ] Convention partagee a l'equipe (lien vers ce document dans Trello).

La configuration et la convention sont preparees. Documenter la date, le resultat
DNS, le HTTP 200 et une capture du navigateur apres le test reel ; ne pas confondre
resolution DNS et fonctionnement de l'URL. La publication dans le depot ne signifie
pas encore que la convention a ete communiquee a tous les membres.

Message propose a copier dans Trello ou la conversation d'equipe :

> Proposition P3 : utilisons `<service>.3.120.212.20.sslip.io`, avec les prefixes
> app, test, argocd, keycloak, dex, grafana et headlamp. Tous pointent sur l'IP fixe
> de kube-1. La convention est dans infrastructure/dns/README.md. HTTP pour les
> premiers tests, puis HTTPS avec cert-manager. Le nom app est temporairement
> utilise par whoami pour validation ; je retirerai cette route avant celle de P2.
