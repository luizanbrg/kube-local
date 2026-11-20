# Verification Keycloak locale - 18 novembre 2026

## Environnement

- Cluster k3d `kubequest-p3` existant, trois noeuds, K3s v1.32.5+k3s1.
- Docker Desktop Linux sur Windows x86_64 ; kubeconfig local separe.
- Keycloak 26.8.2, PostgreSQL 17.7-bookworm, images officielles.
- Traefik et cert-manager deja installes ; variante `local/` appliquee.
- PVC `data-keycloak-db-0` Bound, 1Gi, StorageClass `local-path`.
- Secrets generes aleatoirement dans le cluster uniquement ; aucun mot de passe
  ni jeton affiche, exporte dans Git ou ajoute a ce document.

## Resultats

| Verification | Resultat |
| --- | --- |
| PostgreSQL et Keycloak | Pods Running / Ready |
| Certificat `keycloak-local-tls` | Ready=True |
| Console `/admin/master/console/` | Accessible via HTTPS |
| Discovery `/realms/kubequest/.well-known/openid-configuration` | HTTP 200, issuer local correct |
| Realm importe | kubequest |
| Compte bastian-admin | Cree, membre de kubequest-admins |
| Compte bastian-reader | Cree, membre de kubequest-readers |
| Authentification des deux comptes | Jeton obtenu pour chacun, non affiche |
| Mot de passe incorrect | Refus 400 invalid_grant |
| Remplacement du pod PostgreSQL | Meme PVC retrouve |
| Remplacement du pod Keycloak | Comptes et groupes conserves, deux authentifications a nouveau reussies |

URL utilisee : `https://keycloak.127.0.0.1.sslip.io:8443`.
Les appels HTTPS ont verifie nom DNS et certificat en faisant confiance uniquement
au certificat public auto-signe du Secret, dans le processus Python de test.
Aucune autorite ajoutee au magasin du PC ; l'avertissement navigateur reste attendu.

Les utilisateurs ont ete crees via l'API admin. Les connexions ont ete testees
via un client OIDC public temporaire avec direct grants active pour ce test.
Ce client a ete supprime apres chaque verification, y compris apres le test de
persistance. Aucun client Dex ni integration des outils n'a ete cree.
La connexion interactive complete dans le navigateur n'a pas ete automatisee.

Les mots de passe locaux sont conserves dans le Secret `keycloak-local-test-users`
pour les utilisateurs, et `keycloak-bootstrap` pour l'administrateur temporaire.
Ils sont distincts des futurs identifiants AWS. Le bootstrap admin est conserve
pour permettre les essais locaux ; suivre le guide commun pour son remplacement
avant usage durable. Ne pas publier le contenu de ces Secrets.

## Limites et etat final

Valide localement : demarrage, import du realm, creation des utilisateurs, groupes,
authentification, refus d'un mauvais mot de passe, acces HTTPS et persistance lors
du remplacement des pods. Aucune correction des manifests communs n'a ete necessaire.

Restent a valider : stockage AWS/EFS et permissions, acces public, certificat
Let's Encrypt reconnu, execution ARM64 et future integration Dex/OIDC des outils.
Les regles reseau ont ete appliquees, mais leur isolation complete ne fait pas
l'objet d'un test negatif dans cette verification.

Le premier demarrage et le redemarrage ont pris quelques minutes, a cause de la
preparation de l'image et de l'initialisation de la base. Une image Keycloak
preconstruite/optimisee pourra reduire ce delai ulterieurement.

Le cluster est arrete apres les tests, sans suppression de la base, du PVC ni
des Secrets. Voir [le guide local](README.md) pour le redemarrer et consulter la console.
