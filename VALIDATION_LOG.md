# VALIDATION LOG — Accès Wifirst automatique

Journal append-only. Une entrée = un fait observé, sa source, sa conséquence.
Statuts : `prouvé` (observé directement), `à confirmer` (déduit, non testé), `réfuté`.

---

## V-01 — réseau courant et interface — prouvé — 2026-11-16

- Source : `Get-NetAdapter`, `Get-NetIPConfiguration`.
- Observable : interface `Wi-Fi`, `Killer(R) Wi-Fi 6 AX1650x`, MAC `14-85-7F-28-06-45`,
  IP `10.188.91.52`, passerelle `10.188.0.1`, profil `Wifirst Parc Proby 1 O5`.
- Conséquence : le poste est bien sur le réseau cible ; la carte est celle à piloter.

## V-02 — la valeur `NetworkAddress` est invalide — prouvé — 2026-11-16

- Source : lecture de `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0002`.
- Observable : `NetworkAddress = 12A2C2` (**6 caractères**) ; `Get-NetAdapter` renvoie toujours la MAC
  gravée `14-85-7F-28-06-45`.
- Conséquence : Windows ignore la valeur ; **la MAC n'a jamais changé**, quel que soit le nombre de
  cycles exécutés. Le crédit 24 h « nouvel appareil » ne pouvait pas s'activer.

## V-03 — cause du format : générateur fautif — prouvé — 2026-11-16

- Source : export `DeepSeek - Top UI … 15-43.md`, lignes 6006-6015 (`Get-RandomMac`), et journal
  d'exécution ligne 5915 (`Nouvelle adresse MAC cible : 5A867B`).
- Observable : boucle de 6 tours ajoutant **un caractère** par tour, alors que Windows exige 12
  caractères hexadécimaux sans séparateur.
- Conséquence : correctif obligatoire, plus contrôle de la MAC après redémarrage de la carte.

## V-04 — le script prenait le mauvais fragment — prouvé — 2026-11-16

- Source : même export, lignes 6104-6106 (`fragments_ids."0"`), et
  `evidence/2026-11-16-settings-proby.json`.
- Observable : `fragments_ids."0"` = **17430**, dont `access_type` est `offers`. Le fragment gratuit
  est **17428**, `access_type: freezone`, template `end_user_freezone_signup`.
- Conséquence : le compte était créé sur le tunnel payant, pas sur l'offre gratuite.

## V-05 — champs obligatoires du fragment 17430 (offers) — prouvé

- Source : `evidence/2026-11-16-settings-proby.json`, descripteur de stratégie.
- Observable : `email`, `first_name`, `last_name`, `address` (adresse complète), `password`,
  `password_confirmation`, tous requis.
- Conséquence : un envoi `email` + `cgu` seuls est incomplet.

## V-06 — champs obligatoires du fragment 17428 (freezone) — prouvé

- Source : même fichier.
- Observable : `first_name`, `last_name`, `email`, `password`, `password_confirmation` requis ;
  `newsletter` optionnel ; `cgu` ajouté côté client par le formulaire.
- Conséquence : c'est la charge utile de référence pour le compte gratuit.

## V-07 — cause du `400 Bad Request` — prouvé par recoupement

- Sources : `evidence/2026-11-16-main.2ea93cff.js`, fonction de validation (offset ~2 036 200) et
  composant d'inscription (offset ~2 049 314, contexte `sign-up`) ; journal d'exécution
  (`{"status":400,"error":"Bad Request"}`).
- Observable : la validation client impose `password` ≥ 8 caractères avec majuscule, minuscule et
  chiffre, `password_confirmation` égale, et `cgu` strictement `true`. Champs manquants ⇒ Rails
  rejette la requête.
- Conséquence : le 400 n'était ni un problème d'échappement `curl`, ni un token corrompu. Les
  variantes de payload testées dans l'historique ne pouvaient pas aboutir.

## V-08 — structure réelle de l'appel de création — prouvé

- Source : `main.2ea93cff.js`, offset ~1 985 477.
- Observable : `POST /api/guest_users` avec `{fragment_id, box_token, guest_user, extra}` ; axios en
  `withCredentials: true`, `Content-Type: application/json`, `Accept-Language: fr`.
- Conséquence : l'ancienne structure de haut niveau était juste ; c'est `guest_user` qui était
  incomplet, et le fragment qui était faux.

## V-09 — endpoint de connexion et port — prouvé

- Source : `main.2ea93cff.js`, composant `/connect-wibox` (offset ~2 013 762) et configuration
  `REACT_APP_WIBOX_CONNECT_URL` (offset ~2 197 529).
- Observable : formulaire HTML posté sur `https://wireless.wifirst.net/goform/HtmlLoginRequest`
  (**port 443**), champs `username`, `password`, `success_url`, `error_url`, `update_session=0` ;
  déconnexion sur `HtmlLogout` même port.
- Conséquence : l'usage du port 8090 dans les versions précédentes explique `curl: (28)`.

## V-10 — `connect.wifirst.net/?perform=true` est mort — prouvé — 2026-11-16

- Source : essai navigateur du maître (export, ligne 3781) : page introuvable.
- Conséquence : ne plus l'utiliser.

## V-11 — endpoint de reconnexion — prouvé (lecture), à confirmer (exécution)

- Source : `main.2ea93cff.js`, route `/connect` (offset ~2 012 000) : `GET /api/connect` puis
  `history.push("/connect-wibox", {radiusUser: e.radius})`.
- Observable : le serveur fournit des identifiants `radius` pour l'appareil courant.
- Conséquence : brique de chien de garde pour rétablir une session sans recréer de compte.

## V-12 — secours « accès non payé » — prouvé (lecture)

- Source : `main.2ea93cff.js`, offset ~2 062 100.
- Observable : le bouton d'accès non payé poste `username=PAY/<epoch_ms>@wifirst.net`,
  `password=<epoch_ms>` sur `HtmlLoginRequest`.
- Conséquence : session courte de secours sans création de compte, utile pendant l'attente d'une MAC.

## V-13 — le pilote n'expose pas « Network Address » — prouvé — 2026-11-16

- Source : sortie `Get-NetAdapterAdvancedProperty` de l'historique (lignes 1554-1575).
- Observable : aucune propriété d'adresse MAC dans la liste.
- Conséquence : la méthode `Set-NetAdapterAdvancedProperty` est inopérante ; seul le registre
  (voie Technitium) est candidat, avec vérification obligatoire.

## V-14 — Technitium a déjà écrit une valeur — à confirmer

- Source : déclaration du maître (« ok c fait ! », ligne 1750).
- Observable : une valeur a bien été écrite ensuite dans le registre.
- Reste à confirmer : qu'une valeur **valide de 12 caractères** est réellement appliquée par le
  pilote (test T-1).

## V-15 — absence de dépôt git — prouvé

- Source : `git status` échoue, dossier non versionné.
- Conséquence : sauvegardes manuelles, pas d'historique de diff.

## V-16 — portail joignable et API lisible — prouvé — 2026-11-16

- Source : `GET https://portal.wifirst.net/` → 200 ; `GET /api/settings` → 200 (3 165 octets) ;
  build `main.2ea93cff.js` récupérée (2 201 491 octets).
- Conséquence : l'analyse statique du portail est possible et suffisante pour fixer le contrat d'API.

---

## Résultats de tests

| Test | Date | Statut | Résultat |
|---|---|---|---|
| T-1 MAC seule | 2026-11-16 | **passe** | MAC `02-47-02-AB-3F-0C` appliquée, IP neuve, aucune erreur pilote |
| T-2 API compte | 2026-11-16 | **passe sur la forme** | `400` levé après correction de l'endpoint ; `401` de quota sur MAC déjà consommée |
| T-3 cycle complet | 2026-11-16 | **passe** | MAC neuve, compte `200`, radius, connexion `302`, `generate_204` = 204 |
| T-4 endurance 2 cycles | — | non lancé | — |

---

## V-17 — l'API réelle est `portal-front` / `end_users` — prouvé — 2026-11-16

- Source : capture DevTools du maître (compte créé avec succès) : `POST https://portal-front.wifirst.net/api/end_users` → `201` ;
  `GET https://portal-front.wifirst.net/api/settings?force_production=false`.
- Observable : `portal.wifirst.net/api/guest_users` est l'ancienne API, encore présente dans le bundle
  (`yj`, une occurrence) mais inutilisée ; la vraie fonction est `Lj` → `/api/end_users` avec la clé
  **`end_user`** (offset ~1 988 950).
- Conséquence : cause unique du `400 Bad Request` à corps vide. Tous les essais précédents tapaient la
  mauvaise API.

## V-18 — quota par appareil, signal `401` — prouvé

- Source : trois appels sur la MAC `02-47-02-AB-3F-0C` après deux comptes navigateur.
- Observable : `401 {"error":{"code":401,"message":"Vous êtes arrivé à la limitation de votre offre gratuite…"}}`.
- Conséquence : le quota est bien lié à l'appareil ; un `401` impose une MAC neuve, pas un nouvel e-mail.

## V-19 — cycle complet validé — prouvé — 2026-11-16

- Source : `evidence/2026-11-16-cycle-reussi.txt`, `evidence/2026-11-16-settings-proby.json`.
- Observable : MAC `02-61-BD-54-23-6E`, IP `10.188.53.254`, compte `id 4257504` créé (`200`),
  `radius.login = GUEST/end_user_4257504@wifirst.net`, `HtmlLoginRequest` → `302` vers
  `/connect-redirect`, `generate_204` → `204`.
- Conséquence : la chaîne méthode 24 h est opérationnelle sur cette machine.

## V-21 — session stable en mode continu — prouvé — 2026-11-16 20:42

- Source : journal `logs/20261116-203946.farm.log`, processus actif, MAC `02-AC-50-EB-9C-DD`.
- Observable : compte `4257617` créé avec cookie de session, login `302`, accès `204` maintenu, surveillance
  armée pour 23 h 30 ; aucun changement de MAC depuis.
- Conséquence : le défaut de tenue venait de l'absence du cookie `Portal-AuthToken` sur le login et de son
  absence dans l'appel. Corrigé ; une seule instance doit tourner.
- Reste à confirmer : tenue sur 24 h réelles (T-4).

## V-22 — le front renvoie parfois 504 après création — prouvé

- Source : journaux `20261116-202639` (20:30:45) et `20261116-203512` (20:36:09).
- Observable : passerelle 504 alors que le compte est créé côté serveur.
- Conséquence : après un 504 ou un corps vide, le script teste l'accès réel avant de recréer, au lieu de
  réessayer à l'aveugle.

## V-23 — les coupures venaient d'une session navigateur concurrente — prouvé — 2026-11-16 21:20

- Source : journaux de 20:51 à 21:08 (coupure toutes les ~30 s) puis `logs/20261116-211439.farm.log`.
- Observable : tant qu'un onglet du portail restait ouvert avec l'ancien compte, la box alternait entre les
  deux sessions ; onglets fermés, plus aucune coupure sur cinq minutes.
- Conséquence : une seule identité à la fois. Fermer ou déconnecter le portail dans le navigateur pendant
  que le script tourne.

## V-20 — durée réelle du crédit — à confirmer

- Source : réponse de création, champ `free_ran_elligible: false` ; aucune expiration exposée côté client.
- Observable : le portail n'affiche aucune durée et le bundle ne contient ni `expires_at` ni `remaining`.
- Conséquence : le crédit de 24 h est supposé mais non mesuré ; le chien de garde du script recrée un
  cycle si la session tombe plus tôt.
