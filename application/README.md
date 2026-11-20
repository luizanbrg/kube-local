# Application

Partie "application" du projet : migration d'une app docker-compose vers Kubernetes.

## Contenu

| Dossier | Rôle |
|---|---|
| `src/` | App fournie (Laravel + MySQL), Dockerfile et docker-compose d'origine |
| `helm/kubequest-app/` | Chart Helm de l'app |
| `../infrastructure/gitops/` | Manifests lus par ArgoCD (en cours) |

## Lancer l'app en local (docker-compose)

Depuis la racine du dépôt :

1. `cd application/src`
2. `cp .env.example .env` puis remplir les valeurs vides
3. `docker compose up -d`

## Sécurité

Aucun secret n'est commité : les valeurs sensibles sont dans `.env` (ignoré par Git).
