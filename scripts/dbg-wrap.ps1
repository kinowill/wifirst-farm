$d = 'C:\PROJETS\wifirst internet infini\logs'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$tok = (& curl.exe -k -s -A $ua 'https://wireless.wifirst.net/index.txt') | Out-String
$tok = $tok.Trim()
$attrs = '"first_name":"Jean","last_name":"Dupont","email":"a@b.com","password":"Wf566233zQ","password_confirmation":"Wf566233zQ","cgu":true'

# variante 1 : attributs a la fois a la racine et dans guest_user (theorie wrap_parameters)
$b1 = '{"box_token":"' + $tok + '","fragment_id":17428,' + $attrs + ',"guest_user":{' + $attrs + '}}'
$b1 | Out-File (Join-Path $d 'w1.json') -Encoding ascii -NoNewline
"v1 racine+imbrique => " + (& curl.exe -k -s -A $ua -H 'Content-Type: application/json' -H 'Origin: https://portal.wifirst.net' -X POST 'https://portal.wifirst.net/api/guest_users' --data-binary "@$(Join-Path $d 'w1.json')" -o (Join-Path $d 'w1.body') -w '%{http_code}') + ' ' + (Get-Content (Join-Path $d 'w1.body') -Raw)

# variante 2 : attributs uniquement a la racine
$b2 = '{"box_token":"' + $tok + '","fragment_id":17428,' + $attrs + '}'
$b2 | Out-File (Join-Path $d 'w2.json') -Encoding ascii -NoNewline
"v2 racine seule => " + (& curl.exe -k -s -A $ua -H 'Content-Type: application/json' -H 'Origin: https://portal.wifirst.net' -X POST 'https://portal.wifirst.net/api/guest_users' --data-binary "@$(Join-Path $d 'w2.json')" -o (Join-Path $d 'w2.body') -w '%{http_code}') + ' ' + (Get-Content (Join-Path $d 'w2.body') -Raw)
