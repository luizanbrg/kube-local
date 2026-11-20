- `ansible/` : provisioning du cluster (P1).
- [`ingress/`](README.md) : Traefik en NodePort et application de test (P3).
- [`dns/`](../dns/README.md) : convention des noms publics sslip.io et validation DNS (P3).

Namespaces convenus : `kubequest-app`, `argocd`, `sealed-secrets`, `ingress`,
`cert-manager`, `auth`, `monitoring`, `headlamp`.
Le namespace temporaire `ingress-test` sert uniquement a valider le routage P3.

# Ingress - Follow-up 1 (P3)

Etape suivante : [HTTPS avec cert-manager](../cert-manager/README.md).

Pour integrer les fichiers une fois le cluster P1 pret, suivre le
[guide de deploiement pas a pas](DEPLOIEMENT.md).
Pour verifier la configuration sans AWS, suivre le [guide local k3d](local/README.md).

## Etat

Configuration preparee, pas encore deployee sur AWS. Le cluster doit d'abord etre
provisionne par P1. Aucun test reel d'accessibilite externe n'a encore ete fait.

## Choix justifie

Nous choisissons **Traefik et l'API Kubernetes Ingress**. Le besoin est de router
du trafic HTTP/HTTPS vers des Services suivant leur nom DNS ; l'API Ingress suffit
pour ce jalon, sans ajouter les ressources Gateway API. Traefik prend en charge
Ingress et conserve une continuite avec le Compose fourni, tout en utilisant ici
le provider Kubernetes (pas le provider Docker ni les labels du Compose).

Le chart Helm officiel est epingle en version **42.1.3**, avec Traefik **v3.7.16**.
Cette version demande **Kubernetes >= 1.30** : confirmer la version avec P1 avant
installation. Toute adaptation de version doit etre suivie d'un nouveau rendu Helm.

Le namespace `ingress` heberge le controleur. Un namespace temporaire `ingress-test`
contient le Deployment de demonstration, son Service ClusterIP et son Ingress.
Pour Laravel, l'Ingress restera dans `kubequest-app`, avec son Service (coordination P2).

## Fichiers

| Fichier | Role |
| --- | --- |
| `base/values.yaml` | Configuration Helm Traefik commune au local et a AWS |
| `base/test-app.yaml` | Application de test commune : namespace, Deployment et Service |
| `aws/test-ingress.yaml` | Routage avec le nom public AWS |
| `local/test-ingress.yaml` | Routage avec les noms locaux |

Convention commune : [structure des configurations P3](../STRUCTURE-P3.md).

Les images Traefik et whoami doivent rester compatibles `linux/arm64` pour les
instances t4g.medium. Le test utilise `traefik/whoami:v1.11.0`, disponible en ARM64.
Les requests/limits sont des valeurs initiales de laboratoire a ajuster selon les mesures.
Un seul replica est prevu pour ce premier test ; cela ne demontre pas la haute disponibilite.

## Prerequis avec P1

- Les trois noeuds sont demarres et le cluster est operationnel.
- `kubectl get nodes` fonctionne depuis le terminal de deploiement ; Helm 3 est installe.
- Aucun autre controleur ne gere la classe `traefik`. Si K3s installe deja Traefik,
  convenir avec P1 d'une seule methode de gestion avant de deployer cette release.
- Les NodePorts TCP `30080` et `30443` sont libres.
- L'IP publique fixe de node-1 est bien `3.120.212.20`.
- P1 automatise le raccordement des ports publics vers les NodePorts sur node-1.

### Raccordement reseau indispensable

```text
Internet -> 3.120.212.20:80  -> raccordement sur node-1 -> NodePort 30080
Internet -> 3.120.212.20:443 -> raccordement sur node-1 -> NodePort 30443
                                                     -> Traefik -> Service -> pod
```

Le guide AWS annonce seulement 80/443 ouverts depuis Internet. Definir
`exposedPort: 80` dans Helm ne cree PAS le raccordement du port 80 de la machine
au NodePort 30080. Il faut une redirection persistante ou un relais TCP gere par P1
via Ansible, adapte au reseau du cluster. Cette configuration hote n'est pas fournie
ici car la distribution Kubernetes et le pare-feu ne sont pas encore connus.

Ne pas supposer que `http://3.120.212.20:30080` est accessible depuis Internet.
`externalTrafficPolicy: Cluster` permet de joindre le pod Traefik via node-1 meme
si Kubernetes le place sur un worker. Aucun placement force sur le control plane.

## Installation quand le cluster sera pret

Commandes Bash depuis la racine du depot (le dossier contenant `application/` et
`infrastructure/`), sur un terminal ayant acces au cluster. Depuis node-1, recuperer
d'abord le depot. Verifier le contexte pour viser le bon cluster.

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get ingressclass
kubectl get pods -A
helm list -A

helm repo add traefik https://traefik.github.io/charts
helm repo update

# Rendu local : aucune modification du cluster.
helm template traefik traefik/traefik --version 42.1.3 --namespace ingress --kube-version 1.30.0 -f infrastructure/ingress/base/values.yaml

# Installation de la release, a faire une fois les prerequis confirmes.
helm upgrade --install traefik traefik/traefik --version 42.1.3 --namespace ingress --create-namespace -f infrastructure/ingress/base/values.yaml --wait --timeout 5m

kubectl apply -f infrastructure/ingress/base/test-app.yaml
kubectl apply -f infrastructure/ingress/aws/test-ingress.yaml
kubectl rollout status deployment/ingress-test -n ingress-test --timeout=120s
```

Cette procedure Helm sert au premier bootstrap. Coordonner avec P1 son integration
au GitOps infrastructure ; ne pas faire gerer la meme release par deux mecanismes.
Ce jalon est HTTP uniquement : le NodePort HTTPS est reserve, mais aucun certificat
valide n'est encore configure. cert-manager et la redirection HTTPS viendront ensuite.

## Verification

```bash
kubectl get pods,svc -n ingress
kubectl get pods,svc,ingress -n ingress-test
kubectl describe ingress ingress-test -n ingress-test

# Depuis node-1 : teste le NodePort et le routage, pas l'acces Internet.
curl -i -H 'Host: test.3.120.212.20.sslip.io' http://10.0.0.157:30080/
```

`10.0.0.157` est l'IP privee observee de node-1 ; la confirmer avec P1.
Le Service Traefik doit afficher `80:30080/TCP` et `443:30443/TCP`.
Le champ ADDRESS de l'Ingress peut rester vide avec NodePort : cela n'empeche pas le routage.

Depuis **le PC, hors des VM AWS**, apres raccordement du port 80 :

```powershell
Resolve-DnsName test.3.120.212.20.sslip.io
curl.exe -i http://test.3.120.212.20.sslip.io/
```

Ouvrir aussi `http://test.3.120.212.20.sslip.io/` dans le navigateur.
Attendu : HTTP 200 et une page whoami contenant notamment `Hostname:`.
Pour tester le routage sans dependre de la resolution DNS :

```powershell
curl.exe -i --resolve test.3.120.212.20.sslip.io:80:3.120.212.20 http://test.3.120.212.20.sslip.io/
```

| Symptome | Verification |
| --- | --- |
| Timeout externe, NodePort interne OK | Raccordement 80 -> 30080, Security Group et pare-feu |
| HTTP 404 Traefik | Nom Host, classe Ingress et regle de routage |
| HTTP 503 | Readiness des pods et endpoints du Service de test |
| Pod Pending | Ressources disponibles et contraintes de placement |
| ImagePullBackOff | Acces au registry et disponibilite de l'image ARM64 |

Ne pas cocher l'accessibilite externe sur la seule base d'un port-forward ou d'un curl interne.

## Definition of Done

- [x] Choix Traefik / API Ingress justifie dans ce document.
- [ ] Traefik deploye en NodePort et accessible via kube-1.
- [ ] Application de test accessible depuis Internet (HTTP 200).

Conserver la commande de test, sa date et une capture du navigateur pour la demonstration.
L'app whoami affiche des informations de requete : la retirer apres validation.
Si la route temporaire de l'[issue DNS](../dns/README.md) a ete deployee, la
retirer d'abord : `kubectl delete -f infrastructure/dns/aws/app-test-ingress.yaml`.
Pour retirer uniquement le test (sans toucher au controleur partage) :

```bash
kubectl delete -f infrastructure/ingress/aws/test-ingress.yaml
kubectl delete -f infrastructure/ingress/base/test-app.yaml
```

## References

- [Chart officiel et prerequis](https://github.com/traefik/traefik-helm-chart/blob/v42.1.3/traefik/Chart.yaml)
- [Valeurs du chart](https://github.com/traefik/traefik-helm-chart/blob/v42.1.3/traefik/values.yaml)
- [Ingress avec Traefik](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/)
- [Services NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport)
