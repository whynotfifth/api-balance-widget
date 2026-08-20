# VibeToken 403 诊断脚本：区分 密钥问题 / Cloudflare 拦截 / 代理路由问题
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $dir 'config.json'
$bodyFile = Join-Path $env:TEMP 'vt-test-body.txt'

$c = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$vtKey = "$($c.vibetoken.token)"
$dsKey = "$($c.deepseek.token)"
"VibeToken 密钥: $($vtKey.Length)位/$($vtKey.Substring(0, 6))..."
"DeepSeek 密钥: $($dsKey.Length)位/$($dsKey.Substring(0, 6))..."
$reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
"系统代理: ProxyEnable=$($reg.ProxyEnable) ProxyServer=$($reg.ProxyServer)"
""

$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

function Test-One([string]$label, [string]$url, [string]$key, [string[]]$extraHeaders, [string]$proxy) {
  $argsList = @('-sS', '-m', '25', '-o', $bodyFile, '-w', '%{http_code}', '-H', "Authorization: Bearer $key")
  foreach ($h in $extraHeaders) { $argsList += @('-H', $h) }
  if ($proxy) { $argsList += @('-x', $proxy) }
  $argsList += $url
  $code = & curl.exe @argsList 2>$null
  $body = ''
  if (Test-Path $bodyFile) { $body = (Get-Content $bodyFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue); Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue }
  if ($body -and $body.Length -gt 200) { $body = $body.Substring(0, 200) }
  $body = ($body -replace '\s+', ' ')
  "$label"
  "  状态: HTTP $(if ($code) { $code } else { '连接失败' })"
  if ($body) { "  响应: $body" }
  ""
}

'========== 1) VibeToken 直连（无任何伪装） =========='
Test-One 'GET /v1/usage 直连' 'https://vibetoken.top/v1/usage' $vtKey @() ''
'========== 2) VibeToken 直连 + 完整浏览器请求头 =========='
Test-One 'GET /v1/usage + 浏览器头' 'https://vibetoken.top/v1/usage' $vtKey @("User-Agent: $ua", 'Accept: */*', 'Accept-Language: zh-CN,zh;q=0.9', 'Sec-Fetch-Dest: empty', 'Sec-Fetch-Mode: cors', 'Sec-Fetch-Site: same-origin') ''
'========== 3) VibeToken /v1/models 直连 =========='
Test-One 'GET /v1/models 直连' 'https://vibetoken.top/v1/models' $vtKey @() ''
'========== 4) VibeToken 走系统代理 127.0.0.1:7890 =========='
Test-One 'GET /v1/usage 走代理' 'https://vibetoken.top/v1/usage' $vtKey @() 'http://127.0.0.1:7890'
'========== 5) DeepSeek 对照（应该 200） =========='
Test-One 'GET /user/balance 直连' 'https://api.deepseek.com/user/balance' $dsKey @() ''

'诊断完成，请把以上完整输出发给我。'
