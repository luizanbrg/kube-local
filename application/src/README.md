# Sample app

- Utilise une base mysql
- Site en PHP
- Gestion schéma DB 
- Tests
- Déploiement kube

## Avant tout votre fichier .env 

Copier `.env.example` en `.env` puis remplir les valeurs vides.

## Création du schéma 

```bash
php artisan migrate
```

## Seed du jeu de données 

```bash
php artisan db:seed
```
