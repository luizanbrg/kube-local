# Registry privé (GitHub Container Registry)

Toutes les images du namespace `kubequest-app` viennent de :

```
ghcr.io/epitechmscpropromo2027/t-clo-901-nce-9-1-kube-4/<image>:<tag>
```

- **Pourquoi GHCR** : registry privé, authentifié et en HTTPS, déjà fourni par l'organisation GitHub de l'école,
  rien à héberger ni à faire tourner sur nos nodes (qui n'ont que 4 Go de RAM). Gère les images multi-arch.
- Les packages sont **privés** : sans login, push et pull sont refusés (HTTP 401, voir « Preuves »).
- L'admission policy `03-allowed-images.yaml` refuse toute image qui ne vient pas de ce préfixe.

## Accès

Il faut un token GitHub **classic**, autorisé pour l'organisation (bouton **Configure SSO** → `EpitechMscProPromo2027`
à côté du token). Il faut aussi avoir fait le login SSO de l'organisation sur github.com, sinon le push répond `403 denied`.

| Usage | Scopes du token | Où il sert |
|---|---|---|
| Pousser des images (humains, CI) | `write:packages` (+ `delete:packages` pour nettoyer) | `docker login ghcr.io` sur le PC |
| Tirer des images (cluster) | `read:packages` **uniquement** | Secret `regcred` dans `kubequest-app` |

Le cluster n'a qu'un token en lecture seule : si le Secret fuit, personne ne peut modifier nos images.

Quand une personne pousse une nouvelle image, le package est créé à son nom dans l'organisation.
Pour que les autres puissent pousser dessus : page du package → **Package settings** → **Manage access** → ajouter les membres de l'équipe en *Write*.

## Copier une image publique dans le registry (ex. MySQL)

Nos nodes sont en **ARM64**. Ne pas faire `docker pull` / `tag` / `push` : ça ne copie que l'architecture du PC (amd64).
Copier toutes les architectures d'un coup :

```bash
# 1. vérifier que la source existe en linux/arm64
docker buildx imagetools inspect docker.io/bitnamilegacy/mysql:<tag>
# 2. copier (toutes les architectures)
docker buildx imagetools create \
  -t ghcr.io/epitechmscpropromo2027/t-clo-901-nce-9-1-kube-4/mysql:<tag> \
  docker.io/bitnamilegacy/mysql:<tag>
```

## Secret de pull `regcred`

Les pods le référencent avec :

```yaml
imagePullSecrets:
  - name: regcred
```

**Sur le vrai cluster** : `regcred` sera un **SealedSecret** commité dans Git (jamais le Secret en clair),
une fois le controller Sealed Secrets installé.

**Pour un test local** (kind), créer le Secret à la main. En fish, `read -s` cache le token pendant la saisie :

```fish
kubectl create secret docker-registry regcred -n kubequest-app \
  --docker-server=ghcr.io \
  --docker-username=<pseudo-github> \
  --docker-password=(read -s -P 'Token read:packages : ')
```

## Preuves (testé le 2026-11-06)

| Test | Résultat |
|---|---|
| Push multi-arch avec login (`test:1`, busybox) | ✅ OK, `linux/arm64` présent |
| Pull sans login (`curl https://ghcr.io/token?scope=repository:…/test:pull`) | ✅ refusé, HTTP 401 |
| Push sans login (début d'upload avec un jeton anonyme) | ✅ refusé, HTTP 401 |
| Pod sans `regcred` (kind) | ✅ `ErrImagePull` : `401 Unauthorized` |
| Pod avec `regcred` (token `read:packages`, kind v1.37) | ✅ `Successfully pulled image …/test:1`, logs : `pull OK` |

Rejouer le test du pod :

```bash
kubectl apply -f infrastructure/platform/registry/tests/pull-test.yaml
kubectl get pod -n kubequest-app registry-pull-test     # Completed si regcred est bon, ErrImagePull sinon
kubectl logs -n kubequest-app registry-pull-test        # "pull OK"
kubectl delete pod -n kubequest-app registry-pull-test
```
