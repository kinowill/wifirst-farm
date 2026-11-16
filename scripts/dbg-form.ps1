$d = 'C:\PROJETS\wifirst internet infini\logs'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$tok = (& curl.exe -k -s -A $ua 'https://wireless.wifirst.net/index.txt') | Out-String
$tok = $tok.Trim()

# formulaire Rails classique
$r = & curl.exe -k -s -A $ua -H 'Origin: https://portal.wifirst.net' -X POST 'https://portal.wifirst.net/api/guest_users' `
    --data-urlencode "box_token=$tok" --data-urlencode 'fragment_id=17428' `
    --data-urlencode 'guest_user[first_name]=Jean' --data-urlencode 'guest_user[last_name]=Dupont' `
    --data-urlencode 'guest_user[email]=a@b.com' --data-urlencode 'guest_user[password]=Wf566233zQ' `
    --data-urlencode 'guest_user[password_confirmation]=Wf566233zQ' --data-urlencode 'guest_user[cgu]=true' `
    -o (Join-Path $d 'f1.body') -w '%{http_code}'
"form-urlencoded => $r " + (Get-Content (Join-Path $d 'f1.body') -Raw)

# JSON sans Origin
$b = '{"box_token":"' + $tok + '","fragment_id":17428,"guest_user":{"first_name":"Jean","last_name":"Dupont","email":"a@b.com","password":"Wf566233zQ","password_confirmation":"Wf566233zQ","cgu":true}}'
$b | Out-File (Join-Path $d 'f2.json') -Encoding ascii -NoNewline
$r2 = & curl.exe -k -s -A $ua -H 'Content-Type: application/json' -X POST 'https://portal.wifirst.net/api/guest_users' --data-binary "@$(Join-Path $d 'f2.json')" -o (Join-Path $d 'f2.body') -w '%{http_code}'
"json sans origin => $r2 " + (Get-Content (Join-Path $d 'f2.body') -Raw)

# guest_user en chaine JSON
$inner = '{"first_name":"Jean","last_name":"Dupont","email":"a@b.com","password":"Wf566233zQ","password_confirmation":"Wf566233zQ","cgu":true}'
$b3 = '{"box_token":"' + $tok + '","fragment_id":17428,"guest_user":' + ($inner | ConvertTo-Json) + '}'
$b3 | Out-File (Join-Path $d 'f3.json') -Encoding ascii -NoNewline
$r3 = & curl.exe -k -s -A $ua -H 'Content-Type: application/json' -X POST 'https://portal.wifirst.net/api/guest_users' --data-binary "@$(Join-Path $d 'f3.json')" -o (Join-Path $d 'f3.body') -w '%{http_code}'
"guest_user chaine => $r3 " + (Get-Content (Join-Path $d 'f3.body') -Raw)
