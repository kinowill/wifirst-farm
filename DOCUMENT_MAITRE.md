# DOCUMENT MAÎTRE — Accès Wifirst automatique (24 h renouvelées)

Version : 1.0 — 2026-11-16
Statut : cadrage validé par le maître du projet, **aucun code exécutable produit**, **aucun test lancé**.
Maître du projet : l'utilisateur (ArtLi).

---

## 1. Objet

Obtenir un accès Internet utilisable en continu sur le poste Windows personnel, sur le réseau
Wifirst de la résidence, sans payer, en automatisant :

1. le renouvellement de l'identité réseau (adresse MAC de la carte Wi-Fi) ;
2. la création d'un compte invité neuf sur le portail captif ;
3. la connexion RADIUS qui en découle.

Le moyen choisi par le maître est le **crédit gratuit de 24 h accordé par compte neuf sur appareil
inconnu**, et non plus les sessions courtes de 10 minutes (voir §7).

## 2. Périmètre

Dans le périmètre :
- le poste Windows de l'utilisateur et sa carte Wi-Fi `Killer(R) Wi-Fi 6 AX1650x` (interface `Wi-Fi`) ;
- le portail Wifirst du hotspot courant et son API publique ;
- un script PowerShell unique, lançable par double-clic, gérant tout le cycle.

Hors périmètre (pour l'instant) :
- Raspberry Pi / routeur dédié, mode point d'accès, partage de connexion matériel ;
- téléphone, Android/iOS, randomisation MAC native ;
- usage multi-machines simultané.

## 3. Sources de vérité

Ordre d'autorité : ce document → `ROADMAP.md` → `VALIDATION_LOG.md` → code réellement déployé
(le code réel gagne en cas de conflit).

Faits techniques du portail : mesurés sur la build de production `main.2ea93cff.js` du 2026-11-16,
archive dans `evidence/`.

## 4. État réel du projet (trois états)

| État | Valeur |
|---|---|
| Dépôt modifié | Oui : script `Wifirst-Farm.ps1`, lanceur `.bat`, README, LICENSE, `.gitignore`, documents, `evidence/`. Pas de dépôt git. |
| Prod alignée | Oui en local : script en cours d'exécution (surveillance), MAC `02-AC-50-EB-9C-DD`. |
| Validation réelle | T-1, T-2, T-3 passés ; cycle continu et session stable constatés (V-21). T-4 (24 h) en cours d'observation. |

## 4 bis. Correction majeure du 2026-11-16 (soir)

L'API réellement utilisée par le portail n'est pas `portal.wifirst.net/api/guest_users` mais
**`portal-front.wifirst.net/api/end_users`**, avec la clé `end_user` et des réglages lus sur
`portal-front`. C'était la cause unique du `400 Bad Request` à corps vide : l'ancienne API, encore
présente dans le bundle, n'est plus branchée. Un `401` signifie « quota de cet appareil épuisé » et
impose une MAC neuve. Détail : `VALIDATION_LOG.md` V-17 à V-19.

## 5. Ce qui est prouvé (et qui explique les échecs)

Le script précédent ne pouvait pas fonctionner. Trois défauts indépendants, tous vérifiés :

1. **La MAC n'a jamais changé.** Le registre contient
   `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0002\NetworkAddress = 12A2C2`
   (6 caractères) alors que la carte tourne sur sa MAC gravée `14-85-7F-28-06-45`.
   Le générateur du script (`Get-RandomMac`, export n°1 lignes 6006-6015) boucle 6 fois et ajoute
   **un caractère hexadécimal** par tour : il produit 6 caractères au lieu des 12 exigés par Windows.
   Le pilote ignore donc silencieusement la valeur. Wifirst voyait toujours le même appareil : le
   crédit de 24 h ne pouvait jamais se déclencher.
2. **Mauvais fragment, champs obligatoires absents.** Le script prenait `fragments_ids."0"` = **17430**,
   qui est le fragment *offers* (payant) exigeant `email`, `first_name`, `last_name`, `address`,
   `password`, `password_confirmation`. Il n'envoyait que `email` + `cgu`. Le serveur Rails répond
   donc `400 Bad Request`. Le fragment gratuit est **17428** (`access_type: freezone`).
3. **Mauvais endpoints.** Le script utilisait le port **8090**, fermé sur ce réseau
   (`curl: (28)`), et `connect.wifirst.net/?perform=true`, qui renvoie 404. Le portail actuel
   poste sur `https://wireless.wifirst.net/goform/HtmlLoginRequest` et
   `HtmlLogout` en **port 443**.

## 6. Architecture cible

Un cycle = une nouvelle identité complète, puis 24 h de calme.

1. Déconnexion du portail (443).
2. Génération d'une MAC **12 caractères hexadécimaux**, premier octet `02` (adresse locale, unicast,
   forme recommandée par les outils de spoofing pour les pilotes récalcitrants).
3. Écriture `NetworkAddress` dans la clé de registre de la carte, redémarrage de la carte.
4. **Vérification obligatoire** : `Get-NetAdapter` doit renvoyer la MAC cible. Échec ⇒ 2e essai, puis
   arrêt explicite (jamais de cycle silencieux sur la MAC d'origine).
5. Attente de la réassociation au SSID et d'une IPv4 valide (hors 169.254).
6. Bocal à cookies neuf, `GET /`, puis `GET https://wireless.wifirst.net/index.txt` ⇒ `box_token`.
7. `GET /api/settings` ⇒ sélection dynamique du fragment `access_type: freezone`, puis lecture des
   champs exigés par son descripteur.
8. `POST /api/guest_users` avec `box_token`, `fragment_id`, et `guest_user` rempli selon le
   descripteur (prénom, nom, e-mail unique, mot de passe conforme, confirmation, `cgu: true`,
   `newsletter: false`).
9. `POST https://wireless.wifirst.net/goform/HtmlLoginRequest` (443) avec les identifiants `radius`
   renvoyés, `success_url`, `error_url`, `update_session=0`.
10. Contrôle d'accès réel (`generate_204` = 204), journalisation, puis sommeil de 23 h 45.
11. Chien de garde toutes les 5 min : si Internet tombe, `GET /api/connect` puis reconnexion ;
    si l'accès reste refusé, cycle complet.

Règles de sûreté :
- sauvegarde de la MAC d'origine au premier lancement ;
- restauration de cette MAC sur `Ctrl+C` et sur sortie d'erreur ;
- aucun secret dans les arguments de commande ;
- réponse HTTP complète conservée dans `logs/` pour chaque étape.

## 7. Décision : 24 h plutôt que minutes

Le maître a tranché : farmer les 24 h.

| Critère | Sessions de 10 min | Crédit 24 h |
|---|---|---|
| Cycles par jour | ~144 | 1 |
| Requêtes portail par jour | ~1 400 | ~10 |
| Exposition aux déconnexions | permanente | nulle entre deux cycles |
| Dépendance à la faille « commande » | forte | faible |
| Connexion pendant le travail | coupée toutes les 10 min | stable |

Le mode minutes est conservé comme **secours** pour la fenêtre où la nouvelle MAC n'a pas encore de
crédit : le portail expose un bouton « accès non payé » qui poste simplement
`username=PAY/<epoch_ms>@wifirst.net` et `password=<epoch_ms>` — aucun compte à créer.

## 8. Risques et limites

- Le crédit 24 h est lié à l'appareil **et** au compte : une MAC neuve sans compte neuf ne suffit pas,
  et un compte neuf sur une MAC connue ne rend pas 24 h. Les deux sont nécessaires.
- Le pilote Killer n'expose pas la propriété avancée « Network Address ». Technitium a réussi à écrire
  une MAC, donc la voie registre est plausible, mais un échec reste possible : le test MAC tranche.
- Wifirst peut limiter le nombre de comptes invités par MAC, par IP ou par hotspot, et peut
  blacklister une MAC. Comportement réel inconnu, à mesurer.
- Le portail peut changer de build et de champs à tout moment ; les identifiants de fragment sont
  propres à chaque hotspot et doivent être relus, jamais codés en dur.
- Usage toléré, pas contractuel : aucun engagement de Wifirst.

## 9. Protocole de test (ordre imposé, un test à la fois)

- **T-1 — MAC seule, hors API.** Écrire une MAC `02…` valide, redémarrer la carte, vérifier
  `Get-NetAdapter`. Si la MAC ne change pas : la voie logicielle est morte sur ce pilote, on bascule
  sur le partage de connexion. Aucun intérêt à tester l'API avant.
- **T-2 — API seule, sur la MAC courante.** Bocal neuf, token, settings, un `POST /api/guest_users`
  conforme. Attendu : plus de 400. Un refus de quota est un résultat acceptable ici.
- **T-3 — cycle complet.** Un seul cycle, MAC neuve + compte neuf + connexion.
- **T-4 — endurance.** Deux cycles enchaînés pour vérifier le renouvellement à 24 h.

Chaque test se lance quand le maître le décide : les essais réseau peuvent couper sa connexion.

## 10. Journal des décisions

| Date | Décision | Motif |
|---|---|---|
| 2026-11-16 | Farm 24 h, abandon du mode 10 min comme méthode principale | un cycle par jour, connexion stable |
| 2026-11-16 | Diagnostic avant tout nouveau code | le script précédent échouait pour trois causes non identifiées |
| 2026-11-16 | Sélection dynamique du fragment freezone | les identifiants diffèrent par hotspot |
| 2026-11-16 | Vérification obligatoire de la MAC après écriture | échec silencieux déjà constaté |
