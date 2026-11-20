#!/usr/bin/env bash
# Bootstrap interactif : aucune valeur sensible n'est stockee dans Git.
set -euo pipefail
umask 077
kubectl get namespace auth >/dev/null
for name in keycloak-db keycloak-bootstrap; do
  if kubectl get secret "$name" -n auth >/dev/null 2>&1; then
    echo "Le Secret $name existe deja : aucune modification. Gerer sa rotation separement." >&2
    exit 1
  fi
done
secret_dir=$(mktemp -d)
trap 'rm -f -- "$secret_dir/db-password" "$secret_dir/admin-password" "$secret_dir/username"; rmdir -- "$secret_dir"' EXIT
read -r -s -p 'Mot de passe PostgreSQL (au moins 16 caracteres) : ' db_password
printf '\n'
read -r -s -p 'Mot de passe administrateur temporaire (au moins 16 caracteres) : ' admin_password
printf '\n'
if [[ ${#db_password} -lt 16 || ${#admin_password} -lt 16 ]]; then
  echo 'Les mots de passe doivent avoir au moins 16 caracteres.' >&2
  exit 1
fi
printf '%s' "$db_password" > "$secret_dir/db-password"
printf '%s' "$admin_password" > "$secret_dir/admin-password"
printf '%s' 'bootstrap-admin' > "$secret_dir/username"
unset db_password admin_password
kubectl create secret generic keycloak-db -n auth --from-file=password="$secret_dir/db-password"
kubectl create secret generic keycloak-bootstrap -n auth --from-file=username="$secret_dir/username" --from-file=password="$secret_dir/admin-password"
