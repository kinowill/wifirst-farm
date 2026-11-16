$d = 'C:\PROJETS\wifirst internet infini\logs'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$tok = (& curl.exe -k -s -A $ua 'https://wireless.wifirst.net/index.txt') | Out-String
$tok = $tok.Trim()
"tok_len=$($tok.Length)"

$body = '{"box_token":"' + $tok + '","coupon_code":"TEST","fragment_id":17429}'
$body | Out-File (Join-Path $d 'c1.json') -Encoding ascii -NoNewline
"coupons/check token reel => " + (& curl.exe -k -s -A $ua -H 'Content-Type: application/json' -H 'Origin: https://portal.wifirst.net' -X POST 'https://portal.wifirst.net/api/coupons/check' --data-binary "@$(Join-Path $d 'c1.json')" -o (Join-Path $d 'c1.body') -w '%{http_code}') + ' ' + (Get-Content (Join-Path $d 'c1.body') -Raw)

'{"box_token":"x","coupon_code":"TEST","fragment_id":17429}' | Out-File (Join-Path $d 'c2.json') -Encoding ascii -NoNewline
"coupons/check token x => " + (& curl.exe -k -s -A $ua -H 'Content-Type: application/json' -H 'Origin: https://portal.wifirst.net' -X POST 'https://portal.wifirst.net/api/coupons/check' --data-binary "@$(Join-Path $d 'c2.json')" -o (Join-Path $d 'c2.body') -w '%{http_code}') + ' ' + (Get-Content (Join-Path $d 'c2.body') -Raw)

"connect (sans token) => " + (& curl.exe -k -s -A $ua -H 'Accept: application/json' -o (Join-Path $d 'c3.body') -w '%{http_code}' 'https://portal.wifirst.net/api/connect') + ' ' + (Get-Content (Join-Path $d 'c3.body') -Raw)

"connect avec token query => " + (& curl.exe -k -s -A $ua -H 'Accept: application/json' -o (Join-Path $d 'c4.body') -w '%{http_code}' ("https://portal.wifirst.net/api/connect?box_token=" + [uri]::EscapeDataString($tok))) + ' ' + (Get-Content (Join-Path $d 'c4.body') -Raw)
