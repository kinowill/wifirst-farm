# T-3 : cycle complet (MAC neuve + compte + connexion). Journalise tout.
$ErrorActionPreference = 'Continue'
$d = 'C:\PROJETS\wifirst internet infini\logs'
New-Item -ItemType Directory -Force $d | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $d "$stamp.t3.txt"
function W($m) { $m | Tee-Object -FilePath $log -Append }

$iface = 'Wi-Fi'
$base  = 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$front = 'https://portal-front.wifirst.net'
$ssid = 'Wifirst Parc Proby 1 O5'

# ---- 1. MAC
$adapter = Get-NetAdapter -Name $iface
$guid = $adapter.InterfaceGuid
$orig = ($adapter.MacAddress -replace '-', '')
$key = $null
foreach ($n in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue)) {
    $v = Get-ItemProperty $n.PSPath -ErrorAction SilentlyContinue
    if ($v.NetCfgInstanceId -eq $guid) { $key = $n.PSChildName; break }
}
if (-not $key) { W "RESULT=FAIL cle registre introuvable"; exit 1 }
$orig | Out-File (Join-Path $env:TEMP 'wf_orig_mac.txt') -Encoding ascii

$mac = '02'
1..5 | ForEach-Object { $mac += ('{0:X2}' -f (Get-Random -Minimum 0 -Maximum 256)) }
W "mac_origine=$orig cible=$mac cle=$key"

$applied = $false
foreach ($try in 1, 2) {
    & reg.exe add "$base\$key" /v NetworkAddress /t REG_SZ /d $mac /f | Out-Null
    Disable-NetAdapter -Name $iface -Confirm:$false
    Start-Sleep -Seconds 3
    Enable-NetAdapter -Name $iface -Confirm:$false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 2
        $now = ((Get-NetAdapter -Name $iface -ErrorAction SilentlyContinue).MacAddress) -replace '-', ''
        if ($now -eq $mac) { $applied = $true; break }
        if ($now) { & netsh.exe wlan connect name="$ssid" interface="$iface" | Out-Null }
    }
    if ($applied) { break }
    $mac = '02'
    1..5 | ForEach-Object { $mac += ('{0:X2}' -f (Get-Random -Minimum 0 -Maximum 256)) }
    W "echec application, nouvel essai avec $mac"
}
if (-not $applied) { W "RESULT=FAIL mac non appliquee"; exit 2 }
W "mac_appliquee=$mac"

# ---- 2. attente IP
$ip = $null
for ($i = 0; $i -lt 15; $i++) {
    $ip = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1
    if ($ip) { break }
    & netsh.exe wlan connect name="$ssid" interface="$iface" | Out-Null
    Start-Sleep -Seconds 3
}
if (-not $ip) { W "RESULT=FAIL pas d'IP"; exit 3 }
W "ip=$($ip.IPAddress)"

# ---- 3. portail
$jar = Join-Path $d "$stamp.jar.txt"
& curl.exe -k -s -c $jar -A $ua "$front/" -o NUL

$settings = (& curl.exe -k -s -b $jar -c $jar -A $ua -H 'Accept: application/json' "$front/api/settings?force_production=false") | Out-String
$s = $settings | ConvertFrom-Json
$frag = $s.fragments | Where-Object { $_.access_type -eq 'freezone' } | Select-Object -First 1
if (-not $frag) { W "RESULT=FAIL pas de fragment freezone"; exit 4 }
$fields = $frag.strategy.descriptor.fields
W "hotspot=$($s.hotspot_name) fragment=$($frag.id) champs=$((($fields | ForEach-Object { $_.name }) -join ','))"

# ---- 4. charge utile
$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$pw = 'Wf' + (Get-Random -Minimum 100000 -Maximum 999999) + 'zQ'
$email = "wf$epoch$((Get-Random -Minimum 100 -Maximum 9999))@gmail.com"
$u = [ordered]@{}
foreach ($f in $fields) {
    switch ($f.type) {
        'email'    { $u[$f.name] = $email }
        'password' { $u[$f.name] = $pw }
        'text'     { if ($f.name -match 'first') { $u[$f.name] = 'Jean' } elseif ($f.name -match 'last') { $u[$f.name] = 'Dupont' } else { $u[$f.name] = 'Test' } }
        'tel'      { $u[$f.name] = '0600000000' }
        'number'   { $u[$f.name] = 1 }
        default    { if ($f.required) { $u[$f.name] = 'Test' } }
    }
}
$u['cgu'] = $true
$u['newsletter'] = $false

$resp = $null
for ($try = 1; $try -le 3; $try++) {
    $tok = ((& curl.exe -k -s -b $jar -c $jar -A $ua 'https://wireless.wifirst.net/index.txt') | Out-String).Trim()
    $body = [ordered]@{ box_token = $tok; fragment_id = [int]$frag.id; end_user = $u } | ConvertTo-Json -Depth 6 -Compress
    $jf = Join-Path $d "$stamp.payload.json"
    $body | Out-File $jf -Encoding ascii -NoNewline
    $resp = (& curl.exe -k -s -b $jar -c $jar -A $ua --max-time 40 `
        -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'Accept-Language: fr' `
        -H "Origin: $front" -H "Referer: $front/" -H 'X-Requested-With: XMLHttpRequest' `
        -X POST "$front/api/end_users" --data-binary "@$jf" -w "`nHTTP=%{http_code}") | Out-String
    W "essai $try email=$email`n$resp"
    if ($resp -match '"radius"') { break }
    if ($resp -match 'HTTP=5') { Start-Sleep -Seconds 4; continue }
    break
}

if ($resp -notmatch '"radius"') { W "RESULT=PAS_DE_COMPTE"; exit 5 }
$r = $resp.Substring(0, $resp.LastIndexOf("`nHTTP=")) | ConvertFrom-Json
$login = $r.radius.login
$pass = $r.radius.password
W "radius_login=$login"

# ---- 5. connexion
$lr = (& curl.exe -k -s -S -A $ua -o NUL -D - --max-time 30 `
    --data-urlencode "username=$login" --data-urlencode "password=$pass" `
    --data-urlencode "success_url=$front/connect-redirect" `
    --data-urlencode "error_url=$front/connect-error" `
    --data-urlencode 'update_session=0' `
    'https://wireless.wifirst.net/goform/HtmlLoginRequest' 2>&1) | Out-String
W "login_headers:`n$(($lr -split "`n" | Where-Object { $_ -match '^(HTTP|Location)' }) -join "`n")"

Start-Sleep -Seconds 4
$code = ((& curl.exe -k -s -o NUL -w '%{http_code}' --max-time 8 'https://www.google.com/generate_204') | Out-String).Trim()
W "generate_204=$code"
if ($code -eq '204') { W "RESULT=OK" } else { W "RESULT=LOGIN_NON_EFFECTIF" }

W "PAYLOAD=" + (Get-Content $jf -Raw -Encoding UTF8)
