# Aide-mémoire des commandes

> Les commandes utilisées pour déployer et vérifier l'application, regroupées par thème.
> Les valeurs entre `<…>` sont à remplacer (ex. `<nom-du-pod>`).
> Namespace de l'application : `kubequest-app`.

## Sommaire

1. [Avant toute commande : le bon cluster](#1-avant-toute-commande--le-bon-cluster)
2. [Helm : construire et déployer le chart](#2-helm--construire-et-déployer-le-chart)
3. [Observer le cluster](#3-observer-le-cluster)
4. [Diagnostiquer un problème](#4-diagnostiquer-un-problème)
5. [Agir sur le cluster](#5-agir-sur-le-cluster)
6. [Redémarrer et vérifier que tout est appliqué](#6-redémarrer-et-vérifier-que-tout-est-appliqué)
7. [Secrets](#7-secrets)
8. [Tester l'application](#8-tester-lapplication)
9. [Git : le cycle d'une carte](#9-git--le-cycle-dune-carte)

## 1. Avant toute commande : le bon cluster

| Commande | À quoi elle sert |
|---|---|
| `kubectl config current-context` | Affiche le cluster visé par `kubectl` et `helm`. **À vérifier avant toute action** |
| `kubectl config get-contexts` | Liste tous les clusters connus ; `*` = celui utilisé |
| `kubectl config use-context <contexte>` | Change de cluster |
| `kubectl get nodes` | Liste les machines du cluster et leur état (`Ready` = prête) |
| `k3d cluster list` | (local) Liste les clusters k3d |
| `k3d cluster start <cluster>` / `k3d cluster stop <cluster>` | (local) Démarre / arrête un cluster k3d |

## 2. Helm : construire et déployer le chart

À lancer depuis `application/helm/kubequest-app`.

| Commande | À quoi elle sert |
|---|---|
| `helm dependency update` | Télécharge le chart MySQL (dépendance) et met à jour `Chart.lock` |
| `helm lint .` | Vérifie que le chart est bien écrit, sans rien déployer |
| `helm template kubequest-app . -n kubequest-app` | Affiche les fichiers Kubernetes que Helm **va** générer, sans rien déployer |
| `helm upgrade --install kubequest-app . -n kubequest-app` | Installe le chart, ou le met à jour s'il est déjà installé |
| `helm list -n kubequest-app` | Liste les applications installées par Helm |
| `helm history kubequest-app -n kubequest-app` | Historique des déploiements (révisions) |
| `helm rollback kubequest-app <révision> -n kubequest-app` | Revient à une révision précédente (crée une **nouvelle** révision). Préférer à `kubectl rollout undo`, qui désynchroniserait Helm |
| `helm test kubequest-app -n kubequest-app` | Lance le pod de test : vérifie que l'app répond (`Phase: Succeeded`) |
| `helm upgrade kubequest-app . -n kubequest-app --set <clé>=<valeur>` | Déploie en changeant **une** valeur sans modifier `values.yaml` (ex. simuler une version défaillante) |

## 3. Observer le cluster

Ces commandes ne modifient rien.

| Commande | À quoi elle sert |
|---|---|
| `kubectl -n kubequest-app get pods` | État des pods : `READY`, `STATUS`, `RESTARTS` |
| `kubectl -n kubequest-app get pods -o wide` | Idem + IP et **node** de chaque pod |
| `kubectl -n kubequest-app get pods -w` | Suit les changements en direct (`Ctrl+C` pour quitter) |
| `kubectl -n kubequest-app get pods --show-labels` | Affiche les labels (étiquettes) des pods |
| `kubectl -n kubequest-app get all` | Pods, Services, Deployments, StatefulSets… d'un coup |
| `kubectl -n kubequest-app get pvc` | Volumes persistants demandés (`Bound` = attribué) |
| `kubectl get storageclass` | Types de stockage disponibles dans le cluster |
| `kubectl get validatingadmissionpolicies` | Règles d'admission installées |

## 4. Diagnostiquer un problème

À lancer dans cet ordre (voir aussi la section Dépannage de [application.md](application.md)).

| Commande | À quoi elle sert |
|---|---|
| `kubectl -n kubequest-app describe pod <nom-du-pod>` | Détail d'un pod ; la section **Events** en bas explique pourquoi il ne démarre pas |
| `kubectl -n kubequest-app logs <nom-du-pod>` | Ce que l'application affiche (erreurs Laravel, MySQL…) |
| `kubectl -n kubequest-app logs <nom-du-pod> --previous` | Logs du conteneur **avant** son dernier redémarrage |
| `kubectl -n kubequest-app get events --sort-by=.lastTimestamp` | Tout ce qui s'est passé récemment dans le namespace |
| `kubectl -n kubequest-app logs <nom-du-pod> --tail=20` | Les 20 dernières lignes seulement (alternative à `logs -f`) |
| `watch -n 2 kubectl -n kubequest-app logs <nom-du-pod> --tail=15` | Rafraîchit l'affichage toutes les 2 s (`Ctrl+C` pour quitter) |
| `kubectl -n kubequest-app describe deployment kubequest-app` | État d'une mise à jour : section **Conditions** (`ProgressDeadlineExceeded` = bloquée) et Events |
| `kubectl -n kubequest-app describe secret <nom>` | Liste les clés d'un Secret **sans afficher les valeurs** |

## 5. Agir sur le cluster

Ces commandes **modifient** le cluster.

| Commande | À quoi elle sert |
|---|---|
| `kubectl create namespace kubequest-app` | Crée l'espace de travail de l'application |
| `kubectl apply -f <fichier.yaml>` | Crée ou met à jour les objets décrits dans un fichier |
| `kubectl -n kubequest-app scale deployment kubequest-app --replicas=<n>` | Change temporairement le nombre de pods de l'app (Helm remet la valeur du chart au prochain déploiement) |
| `kubectl -n kubequest-app scale statefulset kubequest-app-mysql --replicas=0` | Éteint MySQL (`=1` pour le rallumer) — utilisé pour tester les probes |
| `kubectl -n kubequest-app rollout restart deployment kubequest-app` | Recrée les pods de l'app un par un |
| `kubectl -n kubequest-app rollout status deployment kubequest-app` | Suit l'avancement d'un déploiement jusqu'à la fin |
| `kubectl apply -f <test.yaml>` puis `kubectl -n kubequest-app delete pod <nom>` | Lance puis supprime un pod de test temporaire (ex. pod qui appelle l'app en continu pendant une mise à jour) |
| `kubectl -n kubequest-app delete pod <nom-du-pod>` | Supprime un pod ; Kubernetes en recrée un automatiquement |
| `kubectl -n kubequest-app exec deploy/kubequest-app -- php artisan migrate --force` | Lance une commande dans un pod de l'app (ici : créer les tables) |

## 6. Redémarrer et vérifier que tout est appliqué

### Vérifier ce que Helm a réellement déployé

| Commande | À quoi elle sert |
|---|---|
| `helm status kubequest-app -n kubequest-app` | État du dernier déploiement (`deployed` = réussi) et numéro de révision |
| `helm get values kubequest-app -n kubequest-app` | Les valeurs **modifiées** utilisées au déploiement (`--all` pour toutes) |
| `helm get manifest kubequest-app -n kubequest-app` | Les fichiers Kubernetes **réellement envoyés** au cluster |

### Vérifier qu'un réglage est bien en place dans le cluster

| Commande | À quoi elle sert |
|---|---|
| `kubectl -n kubequest-app get deployment kubequest-app -o yaml` | La configuration complète du Deployment, telle que le cluster la connaît |
| `kubectl -n kubequest-app get deployment kubequest-app -o jsonpath='{.spec.strategy}'` | Affiche la stratégie de mise à jour (`RollingUpdate`, `maxSurge`, `maxUnavailable`) |
| `kubectl -n kubequest-app get deployment kubequest-app -o jsonpath='{.spec.template.spec.affinity}'` | Affiche **un seul** réglage (ici l'anti-affinité ; remplacer par `.spec.replicas`, `.spec.template.spec.containers[0].resources`…) |
| `kubectl -n kubequest-app get configmap kubequest-app-config -o yaml` | Les valeurs de configuration non sensibles (`DB_HOST`, `APP_ENV`…) |
| `kubectl -n kubequest-app exec deploy/kubequest-app -- printenv DB_HOST` | Ce qu'un pod a **vraiment reçu** pour une variable. ⚠️ Toujours nommer la variable : `printenv` seul afficherait aussi les mots de passe |

### Redémarrer

| Commande | À quoi elle sert |
|---|---|
| `kubectl -n kubequest-app rollout restart deployment kubequest-app` | Recrée les pods de l'app un par un, sans coupure |
| `kubectl -n kubequest-app rollout restart statefulset kubequest-app-mysql` | Redémarre MySQL (coupure de quelques dizaines de secondes, les données sont conservées) |
| `kubectl -n kubequest-app rollout status deployment kubequest-app` | Attend la fin du redémarrage et indique s'il a réussi |
| `kubectl -n kubequest-app wait --for=condition=Ready pod -l app.kubernetes.io/instance=kubequest-app --timeout=180s` | Attend que **tous** les pods (app + MySQL) soient prêts ; échoue au bout de 3 min sinon |

### Repartir de zéro

⚠️ Supprime l'application. À réserver aux tests en local.

| Commande | À quoi elle sert |
|---|---|
| `helm uninstall kubequest-app -n kubequest-app` | Supprime l'app et MySQL. **Le volume de la base est conservé** (protection Kubernetes) |
| `kubectl -n kubequest-app delete pvc data-kubequest-app-mysql-0` | ⚠️ Supprime **définitivement** les données de la base |

Ensuite, réinstaller avec les commandes de [application.md](application.md#commandes) (Secrets, `helm upgrade --install`, migrations).

## 7. Secrets

Les valeurs sont générées au moment de la commande : **jamais écrites dans un fichier ni dans Git**.

| Commande | À quoi elle sert |
|---|---|
| `kubectl -n kubequest-app create secret generic <nom> --from-literal=<CLÉ>="<valeur>"` | Crée un Secret (une clé par `--from-literal`) |
| `openssl rand -base64 24` | Génère un mot de passe aléatoire |
| `kubectl -n kubequest-app get secret <nom> -o jsonpath='{.data.<CLÉ>}' \| base64 -d` | Lit **une** valeur d'un Secret (à éviter : elle s'affiche à l'écran) |
| `unset <VARIABLE>` | Efface une variable du shell après usage |

## 8. Tester l'application

| Commande | À quoi elle sert |
|---|---|
| `kubectl -n kubequest-app port-forward svc/kubequest-app 8090:80` | Rend l'app accessible sur `http://localhost:8090` (en local, le port 8080 est pris par k3d) |
| `curl -s localhost:8090/api/counter/add` | Ajoute 1 au compteur |
| `curl -s localhost:8090/api/counter/count` | Affiche la valeur du compteur |

## 9. Git : le cycle d'une carte

| Commande | À quoi elle sert |
|---|---|
| `git switch dev && git pull` | Revient sur `dev` et récupère la dernière version |
| `git switch -c feat/<sujet>` | Crée une branche pour le travail en cours (ex. `feat/anti-affinity`) |
| `git status` | Fichiers modifiés / nouveaux |
| `git add <fichiers>` | Prépare les fichiers pour le commit |
| `git diff --staged` | **Relit ce qui va partir** (vérifier qu'aucun secret n'y est) |
| `git commit -m ":sparkles: feat: …"` | Enregistre les changements (style gitmoji) |
| `git push -u origin <branche>` | Envoie la branche sur GitHub (puis `git push` tout court) |
| `git log --oneline -5` | Les 5 derniers commits |
