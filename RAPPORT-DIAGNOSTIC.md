# RAPPORT DE DIAGNOSTIC — portail captif Wifirst

Date : 2026-11-16. Cible : hotspot `Wifirst Parc Proby 1 O5`, organisme 165, portail
`https://portal.wifirst.net`, build `main.2ea93cff.js`.
Statut : analyse statique complète, **aucun essai réseau lancé depuis les correctifs**.

---

## 1. Résumé

Le script précédent échouait pour trois raisons cumulées, dont deux le rendaient mécaniquement
inopérant :

1. il annonçait changer la MAC sans la changer (valeur de 6 caractères au lieu de 12) ;
2. il créait le compte sur le fragment payant (`offers`, 17430) en n'envoyant que `email` et `cgu`,
   alors que ce fragment exige six champs ;
3. il visait des endpoints morts (port 8090, `connect.wifirst.net/?perform=true`).

Le `400 Bad Request` n'était donc pas un problème de syntaxe JSON : le serveur refusait une charge
utile incomplète sur le mauvais fragment sont du serveur.

## 2. Le portail, tel qu'il fonctionne réellement

Application React servie par `portal.wifirst.net`, API sur le même hôte.

Points établis par lecture du bundle :

- `GET /api/settings` renvoie, pour le hotspot, la liste des `fragments` et le descripteur des champs
  par stratégie. Aucun fragment n'est identique d'un hotspot à l'autre.
- `POST /api/guest_users` reçoit `{fragment_id, box_token, guest_user, extra}`.
- Le `box_token` provient de `GET https://wireless.wifirst.net/index.txt` (chaîne chiffrée AES,
  à envoyer verbatim).
- L'instance axios du portail tourne en `withCredentials: true`, avec
  `Content-Type: application/json` et `Accept-Language: <locale>`.
- La connexion finale est un formulaire HTML posté sur
  `https://wireless.wifirst.net/goform/HtmlLoginRequest` (port 443) avec
  `username`, `password`, `success_url`, `error_url`, `update_session=0`.
- Le portail distingue les fragments par `access_type` : `offers`, `freezone`, `coupon`.
- Le composant de création gratuite (`end_user_freezone_signup`, contexte `sign-up`) applique la
  validation suivante avant envoi : `first_name`, `last_name`, `email` requis ; `password` ≥ 8
  caractères avec majuscule, minuscule et chiffre ; `password_confirmation` identique ; `cgu`
  strictement `true`. `newsletter` est optionnel.

### Charge utile de référence

```json
{
  "box_token": "<jeton index.txt>",
  "fragment_id": 17428,
  "guest_user": {
    "first_name": "Jean",
    "last_name": "Dupont",
    "email": "jean.dupont.1763300000.4821@gmail.com",
    "password": "Wf7kQm2ZrT",
    "password_confirmation": "Wf7kQm2ZrT",
    "cgu": true,
    "newsletter": false
  }
}
```

`fragment_id` doit toujours être relu dans `/api/settings` (`access_type == "freezone"`), jamais figé.

## 3. Réponse attendue

Succès : `201`, corps contenant `radius: { login, password }`. Les identifiants sont ensuite postés
sur `HtmlLoginRequest`.

Refus attendus, à traiter : `400` (champs manquants ou invalides), `422` (e-mail déjà pris, quota de
comptes atteint), `403` (MAC ou IP bloquée). Le corps complet doit être journalisé : il porte le code
d'erreur exploitable (`errors: { champ: [{ code, message }] }`).

Conséquence d'un succès : crédit gratuit de 24 h sur l'appareil. Le renouvellement exige une MAC
neuve **et** un compte neuf.

## 4. Le défaut MAC, en détail

Valeur constatée dans le registre : `12A2C2`. Format attendu : 12 caractères hexadécimaux, sans
séparateur, premier octet d'adresse locale (`02`).

Générateur fautif :

```powershell
for ($i = 0; $i -lt 6; $i++) { $macBytes += ($hex | Get-Random) }   # 6 caractères, pas 6 octets
```

Générateur correct :

```powershell
$mac = "02"
1..5 | ForEach-Object { $mac += "{0:X2}" -f (Get-Random -Minimum 0 -Maximum 256) }
# $mac = 12 caractères, ex. 02A7F30C1B44
```

Procédure :

1. localiser la sous-clé de classe dont `NetCfgInstanceId` égale le GUID de la carte (ici `0002`) ;
2. `reg add <clé> /v NetworkAddress /t REG_SZ /d <mac> /f` ;
3. `Disable-NetAdapter` puis `Enable-NetAdapter` (pause 3 s) ;
4. **contrôler** : `(Get-NetAdapter -Name 'Wi-Fi').MacAddress` sans séparateurs doit égaler `<mac>` ;
5. en cas d'échec, réessayer une fois avec un autre `02…`, puis s'arrêter ;
6. restauration : `reg delete <clé> /v NetworkAddress /f` + redémarrage carte.

## 5. Erreurs des versions précédentes

| Version | Symptôme | Cause réelle |
|---|---|---|
| 1-3 | crash à « nouvelle adresse MAC » | `Set-NetAdapterAdvancedProperty` alors que le pilote n'expose pas la propriété |
| 4-6 | carte « connectée », puis échec API | MAC de 6 caractères ignorée, donc même appareil ; mauvais fragment |
| 6 | `curl: (28)` | port 8090 fermé, endpoints obsolètes |
| 7-8 | `400 Bad Request` systématique | champs obligatoires absents, fragment `offers` |

## 6. Commandes de test préparées (à lancer seulement sur accord)

### T-1 — MAC seule

```powershell
$key = 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0002'
$mac = '02' + ((1..5 | ForEach-Object { '{0:X2}' -f (Get-Random -Minimum 0 -Maximum 256) }) -join '')
reg add $key /v NetworkAddress /t REG_SZ /d $mac /f
Disable-NetAdapter -Name 'Wi-Fi' -Confirm:$false; Start-Sleep 3; Enable-NetAdapter -Name 'Wi-Fi' -Confirm:$false
Start-Sleep 12
"cible=$mac  constate=$(((Get-NetAdapter -Name 'Wi-Fi').MacAddress) -replace '-','')"
```

Attendu : `cible` = `constate`. Sinon, voie logicielle morte sur ce pilote.

### T-2 — API compte (sur la MAC courante)

1. bocal neuf, `GET /`, `GET https://wireless.wifirst.net/index.txt` ⇒ jeton ;
2. `GET /api/settings` ⇒ localiser `access_type == "freezone"` ;
3. `POST /api/guest_users` avec la charge utile du §2 (e-mail et mot de passe aléatoires).

Attendu : plus de `400`. `201` = chaîne complète possible ; `422` de quota = charge utile acceptée.

### T-3 — cycle complet

MAC neuve, puis T-2, puis `POST HtmlLoginRequest` avec `radius`, puis contrôle
`https://www.google.com/generate_204` = `204`.

## 7. Ce qui reste incertain

- Acceptation par le pilote Killer d'une valeur de 12 caractères (T-1).
- Règle de quota de Wifirst : par MAC, par IP, par e-mail, par hotspot, ou combinée.
- Durée réelle du crédit freezone (24 h annoncées par l'usage, non mesurées).
- Stabilité du SSID après changement de MAC : reconnexion automatique ou manuelle.
- Persistance d'un éventuel blocage après plusieurs cycles.

## 8. Sources

- `evidence/2026-11-16-settings-proby.json` — configuration du hotspot, descripteurs de champs.
- `evidence/2026-11-16-main.2ea93cff.js` — bundle du portail (conventions d'API, validation, endpoints).
- `evidence/2026-11-16-box-token.txt` — jeton d'exemple (lié à la MAC du moment).
- `DeepSeek - Top UI OpenCode style GPT - DeepSeek - 2026-11-12_15-43.md` — historique complet des essais.
