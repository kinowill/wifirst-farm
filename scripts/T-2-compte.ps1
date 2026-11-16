# T-2 : creation d'un compte invite freezone sur la MAC courante. Aucun changement de MAC.
$ErrorActionPreference = 'Continue'
$dir = 'C:\PROJETS\wifirst internet infini\logs'
New-Item -ItemType Directory -Force $dir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$origin = 'https://portal.wifirst.net'
$jar = Join-Path $dir "$stamp.jar.txt"
$out = Join-Path $dir "$stamp.t2.txt"

function W($m) { $m | Tee-Object -FilePath $out -Append }

# 1. cookies
& curl.exe -k -s -S -c $jar -A $ua "$origin/" -o NUL
W "etape1_root=$LASTEXITCODE"

# 2. jeton de box
$token = (& curl.exe -k -s -S -b $jar -c $jar -A $ua 'https://wireless.wifirst.net/index.txt') | Out-String
$token = $token.Trim().Trim('"')
W "etape2_token_len=$($token.Length)"

# 3. settings -> fragment freezone + champs requis
$settingsRaw = & curl.exe -k -s -S -b $jar -c $jar -H 'Accept: application/json' -H 'Accept-Language: fr' -A $ua "$origin/api/settings"
$settingsRaw | Out-File (Join-Path $dir "$stamp.settings.json") -Encoding utf8
$s = $settingsRaw | ConvertFrom-Json
$frag = $s.fragments | Where-Object { $_.access_type -eq 'freezone' } | Select-Object -First 1
if (-not $frag) { W "RESULT=FAIL pas de fragment freezone"; exit 1 }
$fields = $frag.strategy.descriptor.fields
W "etape3_fragment=$($frag.id) champs=$((($fields | ForEach-Object { $_.name }) -join ','))"

# 4. charge utile conforme
$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$pw = 'Wf' + (Get-Random -Minimum 100000 -Maximum 999999) + 'zQ'
$email = "wf$epoch$((Get-Random -Minimum 100 -Maximum 9999))@gmail.com"
$guest = [ordered]@{}
foreach ($f in $fields) {
    switch ($f.type) {
        'email' { $guest[$f.name] = $email }
        'password' {
            if ($f.name -match 'confirmation') { $guest[$f.name] = $pw } else { $guest[$f.name] = $pw }
        }
        'text' {
            if ($f.name -match 'first') { $guest[$f.name] = 'Jean' }
            elseif ($f.name -match 'last') { $guest[$f.name] = 'Dupont' }
            else { $guest[$f.name] = 'Test' }
        }
        'tel' { $guest[$f.name] = '0600000000' }
        'number' { $guest[$f.name] = 1 }
        default { if ($f.required) { $guest[$f.name] = 'Test' } }
    }
}
$guest['cgu'] = $true
$guest['newsletter'] = $false
$body = [ordered]@{ box_token = $token; fragment_id = [int]$frag.id; guest_user = $guest }
$json = $body | ConvertTo-Json -Depth 6 -Compress
$jsonFile = Join-Path $dir "$stamp.payload.json"
$json | Out-File $jsonFile -Encoding ascii
W "etape4_email=$email pw_len=$($pw.Length) fields=$((($guest.Keys) -join ','))"

# 5. creation
$resp = & curl.exe -k -s -S -b $jar -c $jar -A $ua `
    -H 'Content-Type: application/json' -H 'Accept: application/json' `
    -H 'Accept-Language: fr' -H "Origin: $origin" -H "Referer: $origin/end-user/sign-up/$($frag.id)" `
    -H 'X-Requested-With: XMLHttpRequest' -X POST "$origin/api/guest_users" `
    --data-binary "@$jsonFile" -w "`nHTTP=%{http_code}" 2>&1 | Out-String
W "etape5_reponse:`n$resp"

if ($resp -notmatch '"radius"') { W "RESULT=PAS_DE_RADIUS"; exit 2 }

$r = $resp.Substring(0, $resp.LastIndexOf("`nHTTP=")) | ConvertFrom-Json
$login = $r.radius.login
$pass = $r.radius.password
W "etape6_radius_login=$login"

# 6. connexion reelle
$loginResp = & curl.exe -k -s -S -A $ua -o NUL -D - `
    --data-urlencode "username=$login" --data-urlencode "password=$pass" `
    --data-urlencode "success_url=$origin/connect-redirect" `
    --data-urlencode "error_url=$origin/connect-error" `
    --data-urlencode 'update_session=0' `
    'https://wireless.wifirst.net/goform/HtmlLoginRequest' 2>&1 | Out-String
W "etape7_login:`n$(($loginResp -split "`n" | Where-Object { $_ -match '^(HTTP|Location)' }) -join "`n")"

Start-Sleep -Seconds 4
$code = (& curl.exe -k -s -o NUL -w '%{http_code}' --max-time 8 'https://www.google.com/generate_204') | Out-String
W "etape8_generate_204=$code"
if ($code.Trim() -eq '204') { W "RESULT=OK" } else { W "RESULT=LOGIN_NON_EFFECTIF" }
