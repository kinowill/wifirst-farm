# Wifirst-Farm

Renouvelle automatiquement l'accès gratuit Wifirst sur Windows (crédit de 24 h par appareil et
compte neufs), sans navigation manuelle.

> Projet indépendant, sans lien avec Wifirst. Il automatise une offre publique ; il ne casse aucun
> chiffrement et ne revend rien.

## Ce que fait le script

Un cycle = une identité neuve, puis 24 h de calme :

1. déconnexion du portail ;
2. génération et application d'une adresse MAC locale (`02:…`, 12 caractères) ;
3. vérification que la carte a bien pris la nouvelle adresse ;
4. relecture de la configuration du hotspot et du fragment `freezone` ;
5. création d'un compte invité neuf (e-mail et mot de passe aléatoires, CGU acceptées) ;
6. connexion RADIUS et contrôle réel de l'accès ;
7. surveillance : réveil du portail si la session tombe, sinon nouveau cycle.

La MAC d'origine est sauvegardée au premier lancement et restaurée sur `Ctrl+C`.

## Prérequis

- Windows 10/11, PowerShell 5.1, droits administrateur, `curl.exe` (fourni avec Windows) ;
- une carte Wi-Fi dont le pilote accepte le changement d'adresse MAC ;
- être à portée d'un hotspot Wifirst **avec une offre gratuite**.

## Utilisation

- `Wifirst-Farm.bat` : démarre en administrateur et tourne en continu.
- `powershell -ExecutionPolicy Bypass -File Wifirst-Farm.ps1 -Once` : un seul cycle.
- `powershell -ExecutionPolicy Bypass -File Wifirst-Farm.ps1 -Restore` : rend la MAC d'origine.

Réglages en tête de script : interface, SSID, délais.

## Fonctionnement interne

Le portail est une application React. Le script reproduit ses appels :

- `GET https://wireless.wifirst.net/index.txt` → jeton de box ;
- `GET https://portal-front.wifirst.net/api/settings?force_production=false` → fragment `freezone`
  et champs exigés ;
- `POST https://portal-front.wifirst.net/api/end_users` → création du compte, renvoie un couple
  `radius` ;
- `POST https://wireless.wifirst.net/goform/HtmlLoginRequest` → connexion.

Le fragment est toujours relu : ses identifiants changent d'un hotspot à l'autre. Un `401` signifie
« quota de cet appareil épuisé » et déclenche une nouvelle MAC.

## Limites connues

- Les champs du formulaire sont imposés par le serveur ; le script les lit et s'y conforme, mais une
  refonte du portail peut le casser.
- Le crédit réel dépend du hotspot ; le chien de garde recrée un cycle si la session tombe avant.
- Wifirst peut limiter ou bloquer un usage intensif.
- Testé sur un seul modèle de carte (Killer AX1650x) et un seul hotspot.

## Avertissement

Wifirst peut modifier son portail ou ses conditions à tout moment. Aucun engagement de durée.
Usage personnel recommandé.

## Licence

MIT.
