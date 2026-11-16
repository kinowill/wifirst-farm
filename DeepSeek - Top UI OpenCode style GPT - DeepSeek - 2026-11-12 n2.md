La persistance de l'erreur 400 Bad Request après avoir testé plusieurs structures JSON indique que le problème ne vient probablement pas de la syntaxe du payload elle-même, mais d'un paramètre en amont qui rend la requête invalide aux yeux du serveur. D'après le flux documenté, deux suspects se détachent : le fragment\_id et l'URL de l'API settings.

🔍 Le suspect n°1 : le fragment\_id n'est peut-être pas le bon



L'article de référence sur l'automatisation de Wifirst explique que le portail est une application JavaScript qui génère une identité invitée via l'API. Un script Python partagé sur GitHub va plus loin : il ne se contente pas de prendre le premier fragment\_id venu, il itère sur la liste des fragments et sélectionne spécifiquement celui dont le champ access\_type vaut 'freezone'.



Le script actuel récupère un fragment\_id en cherchant la clé "0" dans l'objet fragments\_ids. Il est très possible que ce fragment 0 ne soit pas celui de l'accès gratuit (freezone), ce qui expliquerait le rejet systématique par l'API guest\_users.



Action à tester : Il faut modifier la récupération du fragment\_id pour qu'elle cherche explicitement le fragment freezone.

🌐 Le suspect n°2 : l'URL de l'API settings



Le script utilise https://portal.wifirst.net/api/settings. Cependant, le gist GitHub qui documente ce flux utilise une URL légèrement différente : https://portal-front.wifirst.net/api/settings?force\_production=false. Il est possible que portal.wifirst.net et portal-front.wifirst.net ne servent pas exactement la même configuration, et que le fragment\_id récupéré sur l'un ne soit pas valide pour l'autre.

🛠️ Un script de test pour isoler le problème



Plutôt que de continuer à modifier le script principal à l'aveugle, voici un script de diagnostic autonome. Il ne fait que la partie "récupération du token et du fragment\_id, puis test de l'API guest\_users", sans changement de MAC ni boucle. Il va :



&#x20;   Récupérer les settings depuis les deux URL (portal.wifirst.net et portal-front.wifirst.net).



&#x20;   Afficher la liste des fragments avec leur access\_type.



&#x20;   Tenter de trouver un fragment freezone.



&#x20;   Tester l'appel guest\_users avec le fragment\_id trouvé, en utilisant --data-urlencode pour un encodage propre.



Crée un fichier test-wifirst.ps1 sur ton bureau et colle ceci :

powershell



\# test-wifirst.ps1

$ErrorActionPreference = "Stop"

\[Console]::OutputEncoding = \[System.Text.UTF8Encoding]::new()



$CookieFile = Join-Path $env:TEMP "wifirst\_test\_cookies.txt"

if (Test-Path $CookieFile) { Remove-Item $CookieFile -Force }



$TokenUrl = "https://wireless.wifirst.net/index.txt"

$SettingsUrls = @(

&#x20;   "https://portal.wifirst.net/api/settings",

&#x20;   "https://portal-front.wifirst.net/api/settings?force\_production=false"

)

$GuestUrl = "https://portal.wifirst.net/api/guest\_users"



Write-Host "=== 1. Recuperation du token ===" -ForegroundColor Cyan

$boxTokenRaw = \& curl.exe -k -s -S --connect-timeout 10 -b $CookieFile -c $CookieFile -A "Mozilla/5.0" $TokenUrl 2>\&1

$boxToken = \[string]$boxTokenRaw

if ($boxToken -match "Could not resolve host") { Write-Host "Erreur reseau (DNS)." -ForegroundColor Red; exit 1 }

$boxToken = $boxToken.Trim().Trim('"').Trim("'")

Write-Host "Token (debut) : $($boxToken.Substring(0, \[Math]::Min(40, $boxToken.Length)))..." -ForegroundColor DarkGray



$freezoneFragmentId = $null



foreach ($settingsUrl in $SettingsUrls) {

&#x20;   Write-Host "`n=== 2. Recuperation des settings depuis $settingsUrl ===" -ForegroundColor Cyan

&#x20;   $settingsRaw = \& curl.exe -k -s -S --connect-timeout 10 -b $CookieFile -c $CookieFile -H "Accept: application/json" -A "Mozilla/5.0" $settingsUrl 2>\&1

&#x20;   $settingsJson = \[string]$settingsRaw

&#x20;   

&#x20;   if ($settingsJson -match '"fragments"') {

&#x20;       # Afficher les fragments trouves (extrait simplifie)

&#x20;       $fragmentMatches = \[regex]::Matches($settingsJson, '"id"\\s\*:\\s\*(\\d+).\*?"access\_type"\\s\*:\\s\*"(\[^"]+)"')

&#x20;       if ($fragmentMatches.Count -gt 0) {

&#x20;           Write-Host "Fragments trouves :" -ForegroundColor Yellow

&#x20;           foreach ($m in $fragmentMatches) {

&#x20;               $fid = $m.Groups\[1].Value

&#x20;               $access = $m.Groups\[2].Value

&#x20;               Write-Host "  - ID: $fid, access\_type: $access"

&#x20;               if ($access -eq "freezone" -and -not $freezoneFragmentId) {

&#x20;                   $freezoneFragmentId = $fid

&#x20;               }

&#x20;           }

&#x20;       } else {

&#x20;           Write-Host "Aucun fragment avec 'id' et 'access\_type' trouve dans la reponse." -ForegroundColor DarkYellow

&#x20;           # Fallback : chercher l'ancien format fragments\_ids

&#x20;           if ($settingsJson -match '"fragments\_ids"\\s\*:\\s\*\\{\\s\*"0"\\s\*:\\s\*(\\d+)') {

&#x20;               $freezoneFragmentId = $matches\[1]

&#x20;               Write-Host "Fallback: fragment\_id trouve via fragments\_ids: $freezoneFragmentId" -ForegroundColor DarkYellow

&#x20;           }

&#x20;       }

&#x20;   } else {

&#x20;       Write-Host "La reponse ne contient pas 'fragments'." -ForegroundColor DarkYellow

&#x20;       Write-Host "Debut de la reponse : $($settingsJson.Substring(0, \[Math]::Min(200, $settingsJson.Length)))" -ForegroundColor DarkGray

&#x20;   }

}



if (-not $freezoneFragmentId) {

&#x20;   Write-Host "`nAucun fragment 'freezone' trouve. Arret." -ForegroundColor Red

&#x20;   exit 1

}



Write-Host "`n=== 3. Test de l'API guest\_users avec fragment\_id = $freezoneFragmentId ===" -ForegroundColor Cyan



$email = "$(Get-Date -Format 'yyyyMMddHHmmss')@guest.com"

$guestJson = '{"box\_token":"' + $boxToken + '","fragment\_id":' + $freezoneFragmentId + ',"guest\_user":{"email":"' + $email + '","cgu":true}}'



Write-Host "Payload JSON : $guestJson" -ForegroundColor DarkGray



\# Test avec --data-urlencode pour un encodage propre

$guestRaw = \& curl.exe -k -s -S --connect-timeout 10 `

&#x20;   -b $CookieFile -c $CookieFile `

&#x20;   -H "User-Agent: Mozilla/5.0" `

&#x20;   -H "Content-Type: application/json" `

&#x20;   -H "Accept: application/json" `

&#x20;   -H "Origin: https://portal.wifirst.net" `

&#x20;   -H "Referer: https://portal.wifirst.net/" `

&#x20;   -H "X-Requested-With: XMLHttpRequest" `

&#x20;   -X POST $GuestUrl `

&#x20;   -d $guestJson 2>\&1

$guestResponse = \[string]$guestRaw



Write-Host "`nReponse brute de guest\_users :" -ForegroundColor Yellow

Write-Host $guestResponse -ForegroundColor White



if ($guestResponse -match '"login"\\s\*:\\s\*"(\[^"]+)"') {

&#x20;   Write-Host "`nSUCCES : login trouve = $($matches\[1])" -ForegroundColor Green

} else {

&#x20;   Write-Host "`nECHEC : aucun login dans la reponse." -ForegroundColor Red

}



if (Test-Path $CookieFile) { Remove-Item $CookieFile -Force }



🚀 Comment l'utiliser



&#x20;   Ouvre PowerShell en administrateur (clic droit > Exécuter en tant qu'administrateur).



&#x20;   Place-toi dans le dossier de ton bureau : cd $HOME\\Desktop.



&#x20;   Lance le script : .\\test-wifirst.ps1.



Ce script va afficher la liste des fragments récupérés depuis les deux URL, puis tentera l'appel guest\_users avec le fragment\_id correspondant à freezone. La réponse brute du serveur sera affichée, ce qui permettra de voir si l'erreur 400 persiste et, le cas échéant, d'avoir plus de détails sur la raison du rejet.



Si ce test échoue encore, la réponse brute nous donnera enfin l'indice exact sur ce que le serveur attend.

