$d = 'C:\PROJETS\wifirst internet infini\logs'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$jar = Join-Path $d 'ct.jar'
Remove-Item $jar -ErrorAction SilentlyContinue
& curl.exe -k -s -c $jar -A $ua 'https://portal-front.wifirst.net/' -o NUL
"connect simple => " + (& curl.exe -k -s -b $jar -c $jar -A $ua -H 'Accept: application/json' -o (Join-Path $d 'ct.body') -w '%{http_code}' 'https://portal-front.wifirst.net/api/connect') + ' ' + (Get-Content (Join-Path $d 'ct.body') -Raw)

$tok = ((& curl.exe -k -s -b $jar -c $jar -A $ua 'https://wireless.wifirst.net/index.txt') | Out-String).Trim()
"connect avec box_token => " + (& curl.exe -k -s -b $jar -c $jar -A $ua -H 'Accept: application/json' -o (Join-Path $d 'ct2.body') -w '%{http_code}' ("https://portal-front.wifirst.net/api/connect?box_token=" + [uri]::EscapeDataString($tok))) + ' ' + (Get-Content (Join-Path $d 'ct2.body') -Raw)

"cookies:"; Get-Content $jar -Raw
