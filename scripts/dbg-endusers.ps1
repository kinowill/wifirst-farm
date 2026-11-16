$d = 'C:\PROJETS\wifirst internet infini\logs'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$jar = Join-Path $d 'pf.jar'
Remove-Item $jar -ErrorAction SilentlyContinue

& curl.exe -k -s -c $jar -A $ua 'https://portal-front.wifirst.net/' -o NUL

$tok = (& curl.exe -k -s -b $jar -c $jar -A $ua 'https://wireless.wifirst.net/index.txt') | Out-String
$tok = $tok.Trim()
"token_len=$($tok.Length)"

$email = 'wf' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + '@gmail.com'
$attrs = '"first_name":"Jean","last_name":"Dupont","email":"' + $email + '","password":"Wf566233zQ","password_confirmation":"Wf566233zQ","cgu":true'
$body = '{"box_token":"' + $tok + '","fragment_id":17428,"end_user":{' + $attrs + '}}'
$body | Out-File (Join-Path $d 'pf.json') -Encoding ascii -NoNewline

"POST end_users => " + (& curl.exe -k -s -b $jar -c $jar -A $ua -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'Accept-Language: fr' -H 'Origin: https://portal-front.wifirst.net' -H 'Referer: https://portal-front.wifirst.net/' -X POST 'https://portal-front.wifirst.net/api/end_users' --data-binary "@$(Join-Path $d 'pf.json')" -o (Join-Path $d 'pf.body') -w '%{http_code}')
"reponse=" + (Get-Content (Join-Path $d 'pf.body') -Raw)
"email=$email"
