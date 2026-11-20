# Verification locale du 18 novembre 2026

Test execute sur le cluster k3d `kubequest-p3` existant, avec son kubeconfig
separe et sans modification de la configuration AWS ni du contexte par defaut.

## Installation et emission

- Trois noeuds Ready, K3s v1.32.5+k3s1, Docker Desktop Linux sur Windows x86_64.
- Chart officiel cert-manager v1.21.3 installe avec `../base/values.yaml`.
- Controller, webhook et cainjector Running et Ready (1/1).
- Manifests `test-https.yaml` appliques sans modification.
- Issuer `local-selfsigned` : Ready=True.
- Certificate `ingress-test-local-tls` : Ready=True.
- Secret TLS genere : `ingress-test-local-tls`, dans `ingress-test`.

## Acces HTTPS

| URL | Resultat |
| --- | --- |
| `https://test.127.0.0.1.sslip.io:8443/` | HTTP 200, reponse whoami |
| `https://app.127.0.0.1.sslip.io:8443/` | HTTP 200, reponse whoami |

Premiere verification avec `curl.exe --noproxy "*" -k -i`, puis verification
independante avec Python ssl/urllib :

- Le certificat servi par Traefik est identique au certificat public du Secret
  genere par cert-manager (comparaison DER, pas le certificat Traefik par defaut).
- Les noms DNS et dates sont valides avec confiance explicitement limitee a ce
  certificat dans le processus de test ; HTTP 200 obtenu pour les deux noms.
- Negociation TLS 1.3.
- Sans cette confiance explicite, rejet du certificat auto-signe attendu.
- Aucune autorite ajoutee au magasin de confiance du PC ; aucune cle privee exportee.

Empreinte SHA256 du certificat public lors du test :

```text
708fe159322a954015af4466ff6cb6a834c734c61fa0ff64e9f405ab9a29582b
```

## Portee et suite

Valide : installation cert-manager, emission auto-signee, creation du Secret et
utilisation par Traefik pour servir HTTPS. Les fichiers existants n'ont pas eu
besoin de correction pour ce test.

Non valide ici : ACME HTTP-01, Let's Encrypt staging/production, confiance publique
du navigateur, exposition AWS et execution ARM64. Ces preuves restent a faire
sur le cluster AWS avec ses ports publics et les noms correspondants.

Le cluster est arrete apres les tests, sans suppression des donnees. Pour le
redemarrer depuis PowerShell avec les outils de la session :

```powershell
& "$env:TEMP/kubequest-ingress-tools/k3d.exe" cluster start kubequest-p3
```

Docker Desktop doit etre demarre. L'avertissement navigateur reste normal pour
ces URLs locales auto-signees et ne doit pas etre confondu avec un certificat
Let's Encrypt production reconnu.
