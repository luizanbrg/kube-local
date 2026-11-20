# Deployer Ingress et DNS apres le provisioning P1

Ce guide explique comment utiliser les fichiers prepares dans le depot lorsque
P1 a termine le cluster. Il decrit une procedure a executer : il ne constitue pas
une preuve que le deploiement a deja eu lieu.

## 1. Confirmer les prerequis avec P1

- Les trois instances sont demarrees et les trois noeuds Kubernetes sont Ready.
- Kubernetes est en version 1.30 ou superieure pour le chart retenu (42.1.3).
- Tu disposes d'un acces kubectl au cluster et de Helm 3.
- La classe Ingress `traefik` et la release Helm ne sont pas deja gerees par une
  autre installation. Si P1 a installe K3s avec Traefik, convenir avec lui de la
  configuration de ce controleur avant de poursuivre : ne pas installer un doublon.
- Les NodePorts 30080 et 30443 sont disponibles.
- L'IP elastique de kube-1 est toujours `3.120.212.20`.
- P1 configure via Ansible le passage du port public TCP 80 vers le NodePort 30080
  sur kube-1. Le passage 443 vers 30443 sera necessaire pour HTTPS ensuite.

Le raccordement des ports publics n'est pas realise par les fichiers Helm :
il depend du reseau et du pare-feu prepares par P1. Voir le
[detail reseau](README.md#raccordement-reseau-indispensable).

## 2. Recuperer les fichiers sur kube-1

Sur ton PC, verifier et commiter les fichiers Ingress/DNS, puis les pousser sur
la branche convenue avec l'equipe. Ils doivent etre presents dans le depot distant.

Depuis PowerShell, ouvrir une session sur kube-1 :

```powershell
aws --profile kubequest2 --region eu-central-1 ssm start-session --target i-08b52212f2553dfcb
```

Les commandes suivantes sont a executer dans le shell Linux de kube-1.
Si le depot n'est pas encore present, remplacer les valeurs entre chevrons :

```bash
git clone --branch <branche-equipe> <URL-du-depot> kubequest
cd kubequest
```

Si le depot est deja present, se placer dans son dossier, verifier la branche
et recuperer les modifications (avec un espace de travail sans changements locaux) :

```bash
git status
git branch --show-current
git pull --ff-only
```

Se placer dans le dossier contenant directement `application/` et `infrastructure/`.
Verifier que les fichiers sont bien disponibles :

```bash
ls infrastructure/ingress/base/values.yaml
ls infrastructure/dns/aws/app-test-ingress.yaml
```

Si une erreur d'authentification Git apparait, utiliser la methode d'acces au depot
convenue avec P1 ; ne pas ajouter de jeton ou mot de passe dans les fichiers.

## 3. Verifier l'acces au cluster

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A
kubectl get ingressclass
helm version
helm list -A
```

Verifier le contexte avec P1, les noeuds Ready et l'absence de controleur Traefik
en doublon. Si kubectl est absent ou retourne une erreur de connexion ou de droits,
faire corriger l'acces avec P1 avant d'executer la suite.

## 4. Installer Traefik avec son chart Helm officiel

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --version 42.1.3 \
  --namespace ingress \
  --create-namespace \
  -f infrastructure/ingress/base/values.yaml \
  --wait --timeout 5m

kubectl get pods,svc -n ingress
```

Helm utilise `values.yaml` pour creer les ressources Traefik dans le namespace
`ingress`. Le Service doit etre de type NodePort, avec 30080 pour HTTP et 30443
pour HTTPS. Le pod peut tourner sur un worker : kube-1 reste le point d'entree public.

Ce premier jalon utilise HTTP. La presence du NodePort 30443 ne signifie pas
qu'un certificat HTTPS valide est deja configure.

## 5. Installer l'application de test et les deux routes

La route temporaire `app` est reservee au test : si P2 expose deja Laravel sur
ce nom, ne pas appliquer `app-test-ingress.yaml` et tester Laravel directement.

```bash
kubectl apply -f infrastructure/ingress/base/test-app.yaml
kubectl apply -f infrastructure/ingress/aws/test-ingress.yaml
kubectl apply -f infrastructure/dns/aws/app-test-ingress.yaml

kubectl rollout status deployment/ingress-test -n ingress-test --timeout=120s
kubectl get pods,svc,ingress -n ingress-test
```

Les deux noms menent temporairement au meme Service whoami :

```text
test.3.120.212.20.sslip.io --+
                           +-> IP de kube-1:80 -> NodePort 30080
app.3.120.212.20.sslip.io ---+   -> Traefik -> Service ingress-test -> pod whoami
```

Pour le DNS, aucun composant a deployer : sslip.io renvoie automatiquement
l'IP contenue dans le nom. Voir la [convention des noms](../dns/README.md).

## 6. Tester depuis ton PC, hors des VM AWS

Ouvrir un autre terminal PowerShell local, sans quitter necessairement la session
SSM. Executer :

```powershell
Resolve-DnsName test.3.120.212.20.sslip.io -Type A
Resolve-DnsName app.3.120.212.20.sslip.io -Type A

curl.exe -i --connect-timeout 10 --max-time 20 http://test.3.120.212.20.sslip.io/
curl.exe -i --connect-timeout 10 --max-time 20 http://app.3.120.212.20.sslip.io/
```

Attendu : resolution vers `3.120.212.20`, puis HTTP 200 et `Hostname:` dans la
reponse whoami. Ouvrir les memes URLs dans le navigateur pour la demonstration.

Si le DNS fonctionne mais que HTTP expire, verifier avec P1 le raccordement
80 -> 30080, le Security Group et le pare-feu. Un HTTP 404 indique de verifier
le nom Host, la classe et les regles Ingress ; un HTTP 503 demande de verifier
les pods et les endpoints du Service. Voir aussi le [diagnostic Ingress](README.md#verification).

Un port-forward, un curl depuis kube-1 ou un test contournant le DNS ne suffit
pas a valider l'accessibilite externe de ces deux issues.

## 7. Valider les cartes Trello

- Ingress : choix justifie, Service NodePort accessible via kube-1 et app de test
  repondant depuis Internet.
- DNS : URL `app.3.120.212.20.sslip.io` fonctionnelle et convention communiquee
  a l'equipe avec le lien vers `infrastructure/dns/README.md`.

Conserver la date, les sorties de verification et une capture du navigateur.
Ne cocher les criteres d'exposition qu'apres le test reel.

## 8. Passer du test a Laravel avec P2

Avant que P2 active son Ingress sur le nom `app`, retirer la route temporaire :

```bash
kubectl delete -f infrastructure/dns/aws/app-test-ingress.yaml
```

P2 ajoute ensuite dans son chart Helm un Ingress situe dans `kubequest-app`,
avec le nom `app.3.120.212.20.sslip.io`, la classe `traefik` et son Service Laravel.
Refaire le test externe et verifier que la page Laravel est retournee.
Le DNS et le controleur Traefik restent identiques.

Apres collecte des preuves et quand whoami n'est plus utile, retirer le test :

```bash
kubectl delete -f infrastructure/ingress/aws/test-ingress.yaml
kubectl delete -f infrastructure/ingress/base/test-app.yaml
```

Cela supprime aussi le namespace temporaire `ingress-test`. Ne pas y conserver
d'autres composants. Ne pas desinstaller Traefik, partage par les services du cluster.

## 9. Integrer au GitOps avec P1

Ces commandes servent au premier bootstrap manuel. Les fichiers sont deja dans
le perimetre infrastructure ; convenir avec P1 de leur prise en charge par votre
operateur GitOps. Ne pas faire gerer simultanement la meme installation Traefik
par une release manuelle, un composant integre de la distribution et le GitOps.
Les futurs changements suivront alors votre procedure de commit et reconciliation.
