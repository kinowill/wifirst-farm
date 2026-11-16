$d = 'C:\PROJETS\wifirst internet infini\logs'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$jar = Join-Path $d 'h.jar'
Remove-Item $jar -ErrorAction SilentlyContinue
$g = '{"first_name":"Jean","last_name":"Dupont","email":"a@b.com","password":"Wf566233zQ","password_confirmation":"Wf566233zQ","cgu":true}'

foreach ($n in 1, 2) {
    $tok = (& curl.exe -k -s -b $jar -A $ua -H 'Origin: https://portal.wifirst.net' -H 'Referer: https://portal.wifirst.net/' -H 'Accept: */*' 'https://wireless.wifirst.net/index.txt') | Out-String
    $tok = $tok.Trim()
    $b = '{"box_token":"' + $tok + '","fragment_id":17428,"guest_user":' + $g + '}'
    $b | Out-File (Join-Path $d 'h.json') -Encoding ascii -NoNewline
    $c = (& curl.exe -k -s -b $jar -A $ua -H 'Content-Type: application/json' -H 'Origin: https://portal.wifirst.net' -H 'Referer: https://portal.wifirst.net/end-user/sign-up/17428' -H 'Accept: application/json, text/plain, */*' -H 'Accept-Language: fr-FR,fr;q=0.9' -H 'Sec-Fetch-Site: same-site' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Dest: empty' -X POST 'https://portal.wifirst.net/api/guest_users' --data-binary "@$(Join-Path $d 'h.json')" -o (Join-Path $d 'h.body') -w '%{http_code}')
    "essai $n => $c body=" + (Get-Content (Join-Path $d 'h.body') -Raw)
}
