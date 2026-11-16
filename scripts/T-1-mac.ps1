# T-1 : ecrit une MAC valide (12 caracteres, prefixe 02), redemarre la carte, verifie.
# Revert automatique si la MAC ne s'applique pas ou si aucune IP n'arrive.
$ErrorActionPreference = 'Continue'
$log = Join-Path $env:TEMP 'wf_t1.log'
if (Test-Path $log) { Remove-Item $log -Force }
function W($m) { $m | Tee-Object -FilePath $log -Append }

$iface = 'Wi-Fi'
$base  = 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'

$adapter = Get-NetAdapter -Name $iface
$guid = $adapter.InterfaceGuid
$orig = ($adapter.MacAddress -replace '-', '')
W "carte=$($adapter.InterfaceDescription) guid=$guid mac_origine=$orig"

# localiser la sous-cle de classe de CETTE carte
$key = $null
foreach ($n in (Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue)) {
    $v = Get-ItemProperty $n.PSPath -ErrorAction SilentlyContinue
    if ($v.NetCfgInstanceId -eq $guid) { $key = $n.PSChildName; break }
}
if (-not $key) { W "RESULT=FAIL aucune cle de registre pour ce GUID"; exit 1 }
W "cle=$key"

$mac = '02'
1..5 | ForEach-Object { $mac += ('{0:X2}' -f (Get-Random -Minimum 0 -Maximum 256)) }
W "cible=$mac"

& reg.exe add "$base\$key" /v NetworkAddress /t REG_SZ /d $mac /f | Out-Null
W "ecrit=$($LASTEXITCODE)"

Disable-NetAdapter -Name $iface -Confirm:$false
Start-Sleep -Seconds 3
Enable-NetAdapter -Name $iface -Confirm:$false

$got = $null
$ip  = $null
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 2
    $a = Get-NetAdapter -Name $iface -ErrorAction SilentlyContinue
    if (-not $a -or $a.Status -ne 'Up') { continue }
    $got = ($a.MacAddress -replace '-', '')
    $ip = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1
    if ($ip -and $got -eq $mac) { break }
}

if ($got -ne $mac) {
    W "mac_non_appliquee constate=$got -> relance de l'association"
    & netsh.exe wlan connect name="Wifirst Parc Proby 1 O5" interface="Wi-Fi" | Out-Null
    Start-Sleep -Seconds 10
    $got = (((Get-NetAdapter -Name $iface -ErrorAction SilentlyContinue).MacAddress) -replace '-', '')
}

if ($got -ne $mac) {
    W "RESULT=FAIL mac constante=$got (pilote refuse) -> restauration"
    & reg.exe delete "$base\$key" /v NetworkAddress /f | Out-Null
    Disable-NetAdapter -Name $iface -Confirm:$false; Start-Sleep -Seconds 2
    Enable-NetAdapter -Name $iface -Confirm:$false
    exit 2
}

# association / IP apres application
if (-not $ip) {
    & netsh.exe wlan connect name="Wifirst Parc Proby 1 O5" interface="Wi-Fi" | Out-Null
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 3
        $ip = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1
        if ($ip) { break }
    }
}

$orig | Out-File (Join-Path $env:TEMP 'wf_orig_mac.txt') -Encoding ascii
$state = Get-NetAdapter -Name $iface -ErrorAction SilentlyContinue
W "mac_finale=$((($state.MacAddress) -replace '-', '')) ip=$($ip.IPAddress) statut=$($state.Status)"
if ($ip) { W "RESULT=OK" } else { W "RESULT=NOIP (mac appliquee, pas d'IP)" }
