$d = 'C:\PROJETS\wifirst internet infini\logs'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$s = (& curl.exe -k -s -A $ua -H 'Accept: application/json' 'https://portal.wifirst.net/api/settings') | Out-String
$o = $s | ConvertFrom-Json
"hotspot_id=$($o.hotspot_id) hotspot=$($o.hotspot_name) frags=$((($o.fragments | ForEach-Object { "$($_.id):$($_.access_type)" }) -join ','))"
"ip=" + (Get-NetIPAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4).IPAddress

$tok = (& curl.exe -k -s -A $ua 'https://wireless.wifirst.net/index.txt') | Out-String
$tok = $tok.Trim()
$attrs = '"first_name":"Jean","last_name":"Dupont","email":"a@b.com","password":"Wf566233zQ","password_confirmation":"Wf566233zQ","cgu":true'

foreach ($fid in 17428, 17430, 999999) {
    $b = '{"box_token":"' + $tok + '","fragment_id":' + $fid + ',"guest_user":{' + $attrs + '}}'
    $b | Out-File (Join-Path $d 'g.json') -Encoding ascii -NoNewline
    $r = & curl.exe -k -s -A $ua -H 'Content-Type: application/json' -H 'Origin: https://portal.wifirst.net' -X POST 'https://portal.wifirst.net/api/guest_users' --data-binary "@$(Join-Path $d 'g.json')" -o (Join-Path $d 'g.body') -w '%{http_code}'
    "fragment $fid => $r " + (Get-Content (Join-Path $d 'g.body') -Raw)
}
