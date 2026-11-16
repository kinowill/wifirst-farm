# Wifirst-Farm.ps1
# Renouvelle automatiquement l'acces gratuit Wifirst (24 h par appareil + compte neufs).
# Cycle : deconnexion -> MAC neuve -> compte invite neuf -> connexion -> surveillance.
#
# Lancement simple : double-clic sur Wifirst-Farm.bat
# Un seul cycle       : powershell -ExecutionPolicy Bypass -File Wifirst-Farm.ps1 -Once
# Restauration MAC    : Ctrl+C (ou powershell -File Wifirst-Farm.ps1 -Restore)

param(
    [switch]$Once,
    [switch]$Restore,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# ------------------------------------------------------------------ configuration
$Config = @{
    Interface   = 'Wi-Fi'
    Ssid        = 'Wifirst Parc Proby 1 O5'
    Front       = 'https://portal-front.wifirst.net'
    TokenUrl    = 'https://wireless.wifirst.net/index.txt'
    LoginUrl    = 'https://wireless.wifirst.net/goform/HtmlLoginRequest'
    LogoutUrl   = 'https://wireless.wifirst.net/goform/HtmlLogout'
    UserAgent   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    Renouveler  = 23 * 3600 + 1800      # secondes avant renouvellement
    Surveillance = 10                  # secondes entre deux controles de connexion
    EssaisCompte = 3
    EssaisMac    = 3
}

$Root  = Split-Path -Parent $PSCommandPath
$Logs  = Join-Path $Root 'logs'
$State = Join-Path $Root 'state'
New-Item -ItemType Directory -Force $Logs, $State | Out-Null
$Session = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $Logs "$Session.farm.log"

$RegBase = 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'

function Say {
    param([string]$Message, [string]$Color = 'Gray')
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line -ForegroundColor $Color
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ------------------------------------------------------------------ carte et MAC
function Get-AdapterKey {
    $guid = (Get-NetAdapter -Name $Config.Interface -ErrorAction Stop).InterfaceGuid
    foreach ($sub in Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue) {
        $props = Get-ItemProperty $sub.PSPath -ErrorAction SilentlyContinue
        if ($props.NetCfgInstanceId -eq $guid) { return $sub.PSChildName }
    }
    return $null
}

function Get-MacActuelle {
    ((Get-NetAdapter -Name $Config.Interface -ErrorAction SilentlyContinue).MacAddress) -replace '-', ''
}

function New-MacAleatoire {
    $mac = '02'
    1..5 | ForEach-Object { $mac += ('{0:X2}' -f (Get-Random -Minimum 0 -Maximum 256)) }
    return $mac
}

function Restore-Mac {
    $file = Join-Path $State 'mac_origine.txt'
    if (-not (Test-Path $file)) { Say 'Aucune MAC d''origine enregistree.' 'DarkYellow'; return }
    $orig = (Get-Content $file -Raw).Trim()
    if (-not $orig) { return }
    $key = Get-AdapterKey
    if (-not $key) { Say 'Cle de registre introuvable, restauration impossible.' 'Red'; return }
    Say "Restauration de la MAC d'origine ($orig)..." 'Yellow'
    & reg.exe add "$RegBase\$key" /v NetworkAddress /t REG_SZ /d $orig /f | Out-Null
    Disable-NetAdapter -Name $Config.Interface -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Enable-NetAdapter -Name $Config.Interface -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 8
    & netsh.exe wlan connect name="$($Config.Ssid)" interface="$($Config.Interface)" | Out-Null
}

function Set-MacNeuve {
    $key = Get-AdapterKey
    if (-not $key) { Say 'Cle de registre introuvable.' 'Red'; return $null }

    if (-not (Test-Path (Join-Path $State 'mac_origine.txt'))) {
        (Get-MacActuelle) | Out-File (Join-Path $State 'mac_origine.txt') -Encoding ascii
    }

    for ($essai = 1; $essai -le $Config.EssaisMac; $essai++) {
        $mac = New-MacAleatoire
        Say "MAC cible : $mac (essai $essai)" 'Cyan'
        & reg.exe add "$RegBase\$key" /v NetworkAddress /t REG_SZ /d $mac /f | Out-Null
        Disable-NetAdapter -Name $Config.Interface -Confirm:$false
        Start-Sleep -Seconds 3
        Enable-NetAdapter -Name $Config.Interface -Confirm:$false

        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Seconds 2
            $now = Get-MacActuelle
            if ($now -eq $mac) { Say "MAC appliquee : $mac" 'Green'; return $mac }
            if ($now) { & netsh.exe wlan connect name="$($Config.Ssid)" interface="$($Config.Interface)" | Out-Null }
        }
        Say "La MAC n'a pas ete appliquee (constate : $now)." 'DarkYellow'
    }
    return $null
}

function Wait-Reseau {
    for ($i = 0; $i -lt 20; $i++) {
        $ip = Get-NetIPAddress -InterfaceAlias $Config.Interface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1
        if ($ip) { Say "Association OK (IP $($ip.IPAddress))" 'Green'; return $true }
        & netsh.exe wlan connect name="$($Config.Ssid)" interface="$($Config.Interface)" | Out-Null
        Start-Sleep -Seconds 3
    }
    Say 'Pas d''adresse IP apres 60 s.' 'Red'
    return $false
}

# ------------------------------------------------------------------ portail
function Test-Internet {
    $code = (& curl.exe -k -s -o NUL -w '%{http_code}' --max-time 8 'https://www.google.com/generate_204') | Out-String
    return ($code.Trim() -eq '204')
}

function Invoke-Reveil {
    # Le portail reactive la session existante des qu'on le visite : c'est ce que fait
    # le navigateur. Beaucoup plus econome qu'un nouveau compte.
    Say 'Reveil du portail (session existante)...' 'DarkGray'
    foreach ($url in @("$($Config.Front)/", 'https://portal.wifirst.net/', $Config.TokenUrl)) {
        & curl.exe -k -s -o NUL -A $Config.UserAgent --max-time 5 $url 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        if (Test-Internet) { Say 'Session reactivee.' 'Green'; return $true }
    }
    return $false
}

function Invoke-Entretien {
    # Passage preventif sur le portail : la box prolonge la session au lieu de la couper.
    & curl.exe -k -s -o NUL -A $Config.UserAgent --max-time 8 "$($Config.Front)/" 2>&1 | Out-Null
}

function Invoke-Portal {
    param([string]$Jar, [string]$Method, [string]$Url, [string]$BodyFile)

    $curlArgs = @('-k', '-s', '-b', $Jar, '-c', $Jar, '-A', $Config.UserAgent, '--max-time', '20',
                  '-H', 'Accept: application/json', '-H', 'Accept-Language: fr',
                  '-H', "Origin: $($Config.Front)", '-H', "Referer: $($Config.Front)/",
                  '-H', 'X-Requested-With: XMLHttpRequest')
    if ($Method -eq 'POST') { $curlArgs += @('--max-time', '45', '-X', 'POST', '-H', 'Content-Type: application/json', '--data-binary', "@$BodyFile") }
    return (& curl.exe @curlArgs $Url | Out-String)
}

function Get-Jeton {
    param([string]$Jar)
    return (((& curl.exe -k -s -b $Jar -c $Jar -A $Config.UserAgent $Config.TokenUrl) | Out-String).Trim())
}

function Set-CookieAuth {
    # Le portail pose le jeton de session du compte a la creation. Sans ce cookie,
    # la box autorise puis coupe la session au bout de quelques secondes.
    param([string]$Jar, [string]$Jwt)
    if (-not $Jwt) { return }
    $ligne = @('.wifirst.net', 'TRUE', '/', 'FALSE', '0', 'Portal-AuthToken', $Jwt) -join "`t"
    Add-Content -LiteralPath $Jar -Value $ligne -Encoding ASCII
    Say 'Cookie de session du compte etabli.' 'DarkGray'
}

function New-Compte {
    param([string]$Jar, [int]$FragmentId, $Fields)

    $email = 'wf' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + (Get-Random -Minimum 100 -Maximum 9999) + '@gmail.com'
    $pw = 'Wf' + (Get-Random -Minimum 100000 -Maximum 999999) + 'zQ'

    $user = [ordered]@{}
    foreach ($f in $Fields) {
        switch ($f.type) {
            'email'    { $user[$f.name] = $email }
            'password' { $user[$f.name] = $pw }
            'text'     {
                if ($f.name -match 'first') { $user[$f.name] = 'Jean' }
                elseif ($f.name -match 'last') { $user[$f.name] = 'Dupont' }
                else { $user[$f.name] = 'Test' }
            }
            'tel'      { $user[$f.name] = '0600000000' }
            'number'   { $user[$f.name] = 1 }
            default    { if ($f.required) { $user[$f.name] = 'Test' } }
        }
    }
    $user['cgu'] = $true
    $user['newsletter'] = $false

    for ($essai = 1; $essai -le $Config.EssaisCompte; $essai++) {
        # e-mail et mot de passe neufs a CHAQUE essai : un essai perdu peut avoir cree le compte
        $email = 'wf' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + (Get-Random -Minimum 100 -Maximum 9999) + '@gmail.com'
        $pw = 'Wf' + (Get-Random -Minimum 100000 -Maximum 999999) + 'zQ'
        $user['email'] = $email
        foreach ($f in $Fields) { if ($f.type -eq 'password') { $user[$f.name] = $pw } }

        $token = Get-Jeton -Jar $Jar
        if ($token.Length -lt 20) { Say 'Jeton de box vide ou court.' 'DarkYellow'; Start-Sleep 3; continue }

        $payload = [ordered]@{ box_token = $token; fragment_id = $FragmentId; end_user = $user } |
                   ConvertTo-Json -Depth 6 -Compress
        $file = Join-Path $Logs "$Session.payload.json"
        $payload | Out-File $file -Encoding ascii -NoNewline

        $resp = Invoke-Portal -Jar $Jar -Method POST -Url "$($Config.Front)/api/end_users" -BodyFile $file

        if ($resp -match '"radius"') {
            $data = $resp | ConvertFrom-Json
            Set-CookieAuth -Jar $Jar -Jwt $data.jwt_token
            Say "Compte cree : $($data.email) (id $($data.id))" 'Green'
            $compte = @(
                "email=$($data.email)",
                "password=$pw",
                "login=$($data.radius.login)",
                "id=$($data.id)",
                "mac=$((Get-MacActuelle))",
                "cree=$((Get-Date).ToString('s'))"
            ) -join "`n"
            $compte | Out-File (Join-Path $State 'compte.txt') -Encoding UTF8
            return $data.radius
        }
        # reponse perdue (504 / coupure) mais compte peut-etre cree : on regarde l'acces reel
        if ($resp -match '504' -or $resp.Trim() -eq '') {
            Start-Sleep -Seconds 3
            if (Test-Internet) { Say 'Compte cree malgre la reponse perdue, acces deja actif.' 'Green'; return 'ONLINE' }
        }
        if ($resp -match '"code":401') { Say 'Quota de cet appareil epuise (401).' 'DarkYellow'; return 'QUOTA' }
        Say "Creation refusee (essai $essai) : $($resp.Trim())" 'DarkYellow'
        Start-Sleep -Seconds 4
    }
    return $null
}

function Connect-Portal {
    param($Radius, [string]$Jar)
    for ($essai = 1; $essai -le 3; $essai++) {
        $h = (& curl.exe -k -s -S -b $Jar -c $Jar -A $Config.UserAgent -o NUL -D - --max-time 30 `
            --data-urlencode "username=$($Radius.login)" `
            --data-urlencode "password=$($Radius.password)" `
            --data-urlencode "success_url=$($Config.Front)/connect-redirect" `
            --data-urlencode "error_url=$($Config.Front)/connect-error" `
            --data-urlencode 'update_session=1' $Config.LoginUrl 2>&1) | Out-String
        $head = ($h -split "`n" | Where-Object { $_ -match '^(HTTP|Location)' }) -join ' | '
        Say "Connexion (essai $essai) : $head" 'Gray'
        Start-Sleep -Seconds 3
        if (Test-Internet) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Invoke-Secours {
    # Session courte "acces non paye" : evite de rester sans rien.
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Say 'Tentative de session de secours (10 min)...' 'DarkYellow'
    & curl.exe -k -s -S -A $Config.UserAgent -o NUL --max-time 30 `
        --data-urlencode "username=PAY/$stamp@wifirst.net" `
        --data-urlencode "password=$stamp" `
        --data-urlencode "success_url=$($Config.Front)/connect-redirect" `
        --data-urlencode "error_url=$($Config.Front)/connect-error" `
        --data-urlencode 'update_session=0' $Config.LoginUrl 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    return (Test-Internet)
}

function Disconnect-Portal {
    & curl.exe -k -s -o NUL --max-time 10 -X POST $Config.LogoutUrl `
        -d 'logout_session=Logout' -d "success_url=$($Config.Front)/" -d "error_url=$($Config.Front)/" | Out-Null
}

function Clear-Portal {
    $jar = Join-Path $Logs "$Session.jar.txt"
    Remove-Item $jar -ErrorAction SilentlyContinue
    & curl.exe -k -s -c $jar -A $Config.UserAgent "$($Config.Front)/" -o NUL

    $settings = (& curl.exe -k -s -b $jar -c $jar -A $Config.UserAgent -H 'Accept: application/json' "$($Config.Front)/api/settings?force_production=false") | Out-String
    if (-not $settings) { Say 'Reglages du portail illisibles.' 'Red'; return $false }
    $cfg = $settings | ConvertFrom-Json
    $frag = $cfg.fragments | Where-Object { $_.access_type -eq 'freezone' } | Select-Object -First 1
    if (-not $frag) { Say 'Aucune offre gratuite sur ce hotspot.' 'Red'; return $false }

    $fields = $frag.strategy.descriptor.fields
    Say "Hotspot : $($cfg.hotspot_name) - fragment $($frag.id) - champs : $((($fields | ForEach-Object { $_.name }) -join ','))" 'Gray'

    $radius = New-Compte -Jar $jar -FragmentId $frag.id -Fields $fields
    if ($radius -eq 'QUOTA') { return 'QUOTA' }
    if ($radius -eq 'ONLINE') { return $true }
    if (-not $radius) { return $false }
    if (Connect-Portal -Radius $radius -Jar $jar) {
        $script:radiusCourant = $radius
        $script:jarCourant = $jar
        Start-Sleep -Seconds 10
        if (-not (Test-Internet)) {
            Say 'Session retombee juste apres le login, nouvelle tentative de connexion.' 'DarkYellow'
            if (-not (Connect-Portal -Radius $radius -Jar $jar)) { return $false }
        }
        foreach ($i in 1, 2) {
            Start-Sleep -Seconds 10
            if (-not (Test-Internet)) { Say "Session instable (controle $i/2)." 'DarkYellow'; return $false }
        }
        return $true
    }

    Say 'Connexion refusee, session de secours.' 'DarkYellow'
    return (Invoke-Secours)
}

function Invoke-Cycle {
    param([int]$Profondeur = 0, [switch]$Force)

    if (-not $Force -and (Invoke-Reveil)) { return $true }

    Disconnect-Portal
    Start-Sleep -Seconds 2

    if (-not (Set-MacNeuve)) { Say 'Impossible de changer la MAC, arret.' 'Red'; return $false }
    if (-not (Wait-Reseau)) { return $false }

    $r = Clear-Portal
    if ($r -eq 'QUOTA') {
        if ($Profondeur -ge 3) { Say 'Trop de MAC deja consommees de suite.' 'Red'; return $false }
        Say 'Appareil deja consomme, nouveau cycle avec une autre MAC.' 'DarkYellow'
        return Invoke-Cycle -Profondeur ($Profondeur + 1)
    }
    if ($r) { return $true }

    # echec de creation (souvent un 504 du portail) : on garde la MAC et on retente plus tard
    foreach ($pause in 30, 90) {
        Say "Portail en echec, nouvelle tentative sur la meme MAC dans $pause s." 'DarkYellow'
        Start-Sleep -Seconds $pause
        if (Test-Internet) { return $true }
        $r = Clear-Portal
        if ($r -eq 'QUOTA') { break }
        if ($r) { return $true }
    }
    return $false
}

# ------------------------------------------------------------------ principal
if (-not (Test-Admin)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    exit
}

if ($Restore) { Restore-Mac; exit }

Clear-Host
Write-Host '============================================' -ForegroundColor Magenta
Write-Host '   Wifirst - renouvellement automatique' -ForegroundColor Magenta
Write-Host '============================================' -ForegroundColor Magenta
Write-Host "Journal : $LogFile" -ForegroundColor DarkGray
Write-Host 'Ctrl+C pour arreter et restaurer la MAC.' -ForegroundColor DarkYellow
Say 'Demarrage' 'White'

$premierCycle = $true
while ($true) {
    try {
        if (-not (Test-Internet) -or $Force) {
            if (-not (Invoke-Cycle -Force:$Force)) {
                Say 'Cycle incomplet, nouvelle tentative dans 20 s.' 'Red'
                Start-Sleep -Seconds 20
                continue
            }
            Say 'Cycle termine : acces actif.' 'Green'
        }
        else {
            Say 'Deja connecte.' 'Green'
        }

        if ($Once -and $premierCycle) { Say 'Mode -Once : fin du cycle.' 'DarkYellow'; break }
        $premierCycle = $false

        Say "Surveillance active (renouvellement au plus tard dans $([math]::Round($Config.Renouveler / 60)) min)." 'DarkGray'
        $limite = (Get-Date).AddSeconds($Config.Renouveler)
        $tick = 0
        while ((Get-Date) -lt $limite) {
            Start-Sleep -Seconds $Config.Surveillance
            $tick++
            # toutes les 60 s, on reprend la main sur la session : un navigateur connecte
            # finit toujours par perdre la course.
            if ($tick % 6 -eq 0 -and $script:radiusCourant) {
                if (-not (Connect-Portal -Radius $script:radiusCourant -Jar $script:jarCourant)) {
                    Say 'Reprise de session impossible, reveil.' 'DarkGray'
                }
            }
            Invoke-Entretien
            if (-not (Test-Internet)) {
                Say 'Connexion perdue, reveal immediat.' 'DarkYellow'
                $revenu = Invoke-Reveil
                if ($revenu) { continue }
                Say 'Reveil impossible, cycle complet.' 'DarkYellow'
                break
            }
        }
        if ((Get-Date) -ge $limite) { Say 'Renouvellement programme atteint.' 'Cyan' }
    }
    catch {
        Say "Erreur : $($_.Exception.Message)" 'Red'
        Start-Sleep -Seconds 30
    }
}








