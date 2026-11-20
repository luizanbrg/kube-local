# Admission policies (ValidatingAdmissionPolicy, CEL)

Règles vérifiées par l'API Kubernetes **avant** qu'un objet soit créé ou modifié.
Si une règle n'est pas respectée, l'objet est refusé avec un message qui dit quoi corriger.

- Outil natif de Kubernetes (pas de Kyverno/Gatekeeper à installer) : `admissionregistration.k8s.io/v1`, Kubernetes ≥ 1.30.
- Appliqué **uniquement** au namespace `kubequest-app` (via les `ValidatingAdmissionPolicyBinding`).
- Objets contrôlés : Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs (création et modification).
  Un Deployment non conforme est donc refusé dès le `kubectl apply` / la sync ArgoCD, et pas seulement au moment de créer ses pods.

## Les 5 règles

| Fichier | Règle | Pourquoi |
|---|---|---|
| `01-non-root.yaml` | `runAsNonRoot: true` (pod ou conteneur), pas de `runAsUser: 0`, pas de `privileged`, `allowPrivilegeEscalation: false` — initContainers compris | Un conteneur piraté ne doit pas pouvoir devenir root sur la machine |
| `02-resources.yaml` | `requests` et `limits`, `cpu` et `memory`, sur chaque conteneur | Nos nodes n'ont que 4 Go de RAM : un pod sans limite peut faire tomber la machine |
| `03-allowed-images.yaml` | Image venant de `ghcr.io/epitechmscpropromo2027/t-clo-901-nce-9-1-kube-4/`, avec un tag explicite, jamais `latest` (digest `@sha256:` accepté) | Seules nos images vérifiées tournent, et une version précise = déploiement reproductible |
| `04-labels.yaml` | Labels `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/part-of=kubequest` | Labels recommandés Kubernetes : retrouver/filtrer tout ce qui appartient au projet |
| `05-readiness-probe.yaml` | `readinessProbe` sur chaque conteneur des **Deployments et StatefulSets** uniquement | Sans readiness, une v2 cassée recevrait du trafic. Pas exigée sur les Jobs/CronJobs (ex. backup) qui ne reçoivent pas de trafic |

Pour changer l'adresse du registry, modifier uniquement la variable `allowedPrefix` dans `03-allowed-images.yaml`.

À savoir :
- La règle 1 lit le **spec du pod**, pas le `USER` du Dockerfile : il faut écrire `runAsNonRoot: true` dans le chart.
- Pour un CronJob, mettre les labels aussi dans `spec.jobTemplate.metadata.labels` (les Jobs créés les reprennent).
- Si un objet viole plusieurs règles, Kubernetes n'affiche que le message de la première règle qui refuse.

## Installer

Depuis la racine du dépôt :

```bash
kubectl apply -k infrastructure/platform/admission-policies/
kubectl get validatingadmissionpolicy,validatingadmissionpolicybinding
```

## Tester (preuve pour la soutenance)

`--dry-run=server` envoie l'objet à l'API (donc passe par les règles) sans rien créer.

```bash
cd infrastructure/platform/admission-policies

# Doit être REFUSÉ (nginx:latest, root, sans resources ni labels)
kubectl apply --dry-run=server -f tests/bad-nginx-latest.yaml

# Chaque objet viole UNE règle : 7 refus attendus, un message par règle
kubectl apply --dry-run=server -f tests/bad-cases.yaml

# Doivent être ACCEPTÉS (le CronJob n'a pas de readinessProbe, c'est voulu)
kubectl apply --dry-run=server -f tests/ok-deployment.yaml -f tests/ok-cronjob.yaml

# Le même nginx passe dans un autre namespace : les règles ne visent que kubequest-app
kubectl run nginx --image=nginx:latest -n default --dry-run=server
```

Résultat attendu pour `bad-nginx-latest.yaml` :

```
The pods "policy-test-nginx" is invalid: : ValidatingAdmissionPolicy 'kubequest-resources' with binding
'kubequest-resources' denied request: resources.requests et resources.limits (cpu + memory) sont obligatoires.
Conteneurs en faute : nginx
```

Testé le 2026-11-06 sur un cluster local kind (Kubernetes v1.37.0) : tous les cas se comportent comme prévu,
et les pods créés par un Deployment / un CronJob conformes sont bien acceptés.

### Tester en local avec kind

Depuis la racine du dépôt (revenir à celle-ci si vous avez exécuté le `cd` de la section précédente) :

```bash
kind create cluster --name policies
kubectl create namespace kubequest-app
kubectl apply -k infrastructure/platform/admission-policies/
# ... commandes de test ci-dessus ...
kind delete cluster --name policies
```
