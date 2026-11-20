# Tester Traefik localement avec k3d

## Resultat du test du 20 octobre 2026

Test execute sur Windows avec Docker Desktop Linux (x86_64), k3d 5.8.3 et Helm
3.19.0. Le cluster local `kubequest-p3` a trois noeuds Ready, en K3s v1.32.5+k3s1.
Traefik v3.7.16 (chart 42.1.3) est deploye sur agent-0 ; whoami sur agent-1.

| Verification | Resultat |
| --- | --- |
| Service Traefik | NodePort, 80:30080/TCP et 443:30443/TCP |
| DNS test/app.127.0.0.1.sslip.io | 127.0.0.1 |
| HTTP test.127.0.0.1.sslip.io:8080 | 200 OK, reponse whoami |
| HTTP app.127.0.0.1.sslip.io:8080 | 200 OK, reponse whoami |
| Host inconnu vers le meme port | 404, aucune route correspondante |

Le test a permis de corriger les valeurs du chart : `type: NodePort` doit se
trouver sous `service.spec`, et non directement sous `service`. La release a
ensuite ete mise a jour avec le fichier corrige et son type effectif verifie.
Le cluster est laisse demarre pour permettre de consulter les URLs.

## Procedure reproductible

Ce test utilise les memes valeurs Helm Traefik que celles preparees pour AWS.
Seuls le reseau d'entree et les noms DNS changent. Il valide le routage local,
pas l'exposition publique sur kube-1 ni la compatibilite d'execution ARM64.

## Prerequis

Docker Desktop demarre avec les conteneurs Linux, k3d 5.8.3, Helm 3 et kubectl.
Prevoir les ressources pour un serveur K3s et deux workers. Les ports locaux
8080 et 8443 doivent etre disponibles. Commandes PowerShell depuis la racine du
depot contenant `application/` et `infrastructure/`.

Si les outils ne sont pas dans le PATH, utiliser leur chemin complet. Pour la
session preparee par l'assistant, les executables sont dans le dossier temporaire
`$env:TEMP/kubequest-ingress-tools` (k3d.exe et windows-amd64/helm.exe).

## Creer le cluster et un acces separe

```powershell
k3d cluster create --config infrastructure/ingress/local/k3d.yaml --wait --timeout 180s
$p3Kubeconfig = k3d kubeconfig write kubequest-p3
kubectl --kubeconfig $p3Kubeconfig get nodes
```

La configuration ne modifie pas le contexte Kubernetes par defaut. Toujours
utiliser `--kubeconfig $p3Kubeconfig` pour viser ce cluster. Le fichier genere
contient des identifiants : ne pas le commiter. K3s est epingle en v1.32.5-k3s1
pour ce test ; ce choix n'impose pas la version du cluster AWS de P1.

Traefik et ServiceLB integres a K3s sont desactives. Le port local 8080 est
raccorde au NodePort 30080 du serveur, et 8443 au NodePort 30443.

## Installer notre Traefik et whoami

```powershell
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik --version 42.1.3 --namespace ingress --create-namespace --kubeconfig $p3Kubeconfig -f infrastructure/ingress/base/values.yaml --wait --timeout 5m
kubectl --kubeconfig $p3Kubeconfig apply -f infrastructure/ingress/base/test-app.yaml
kubectl --kubeconfig $p3Kubeconfig apply -f infrastructure/ingress/local/test-ingress.yaml
kubectl --kubeconfig $p3Kubeconfig rollout status deployment/ingress-test -n ingress-test --timeout=120s
```

Ne pas appliquer les Ingress AWS pour ce test : leurs noms pointent vers kube-1.

## Verifier

```powershell
kubectl --kubeconfig $p3Kubeconfig get pods,svc -n ingress
kubectl --kubeconfig $p3Kubeconfig get pods,svc,ingress -n ingress-test
Resolve-DnsName test.127.0.0.1.sslip.io -Type A
Resolve-DnsName app.127.0.0.1.sslip.io -Type A
curl.exe --noproxy "*" -i --connect-timeout 5 --max-time 15 http://test.127.0.0.1.sslip.io:8080/
curl.exe --noproxy "*" -i --connect-timeout 5 --max-time 15 http://app.127.0.0.1.sslip.io:8080/
```

Attendu : IP 127.0.0.1, HTTP 200 et `Hostname:` dans les deux reponses.
Ouvrir les memes URLs dans le navigateur. Si le resolveur bloque les noms vers
127.0.0.1, un test de routage independant du DNS est possible :

```powershell
curl.exe --noproxy "*" -i -H "Host: test.127.0.0.1.sslip.io" http://127.0.0.1:8080/
```

Ce dernier test ne valide pas le DNS. Le port 8443 est seulement reserve : ce
guide ne configure ni certificat Let's Encrypt ni HTTPS reconnu.

## Arreter ou supprimer le test

```powershell
# Arret reversible pour liberer CPU/RAM ; redemarrer avec cluster start.
k3d cluster stop kubequest-p3
k3d cluster start kubequest-p3

# Seulement quand les donnees de ce cluster local ne sont plus necessaires :
k3d cluster delete kubequest-p3
```

References : [exposition NodePort k3d](https://k3d.io/stable/usage/exposing_services/)
et [procedure AWS](../DEPLOIEMENT.md).
