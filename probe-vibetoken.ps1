# ============================================================================
#  VibeToken 接口探测脚本（第二版：探测常见余额查询接口）
#
#  用法：
#   1. 把 config.json 里 vibetoken.token 填上你手上的 API 密钥（sk-xxx）
#   2. 双击 probe-vibetoken.bat 运行本脚本
#   3. 把窗口里的输出完整复制发给作者
#
#  已确认：/v1/models 用 Bearer(API密钥) 返回 200，说明站点是 OpenAI 兼容中转站。
#  本脚本用 Bearer 认证逐一对常见的"余额查询"接口做探测。
# ============================================================================
$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $dir 'config.json'

$token = ''
if (Test-Path $cfgPath) {
  try {
    $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.vibetoken.token) { $token = "$($cfg.vibetoken.token)".Trim() }
  } catch { }
}

"=============================================="
" VibeToken 余额接口探测   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
"=============================================="
if ($token) { "已配置凭据：是（长度 $($token.Length)，内容已隐藏）" }
else { "已配置凭据：否（先往 config.json 的 vibetoken.token 填 API 密钥再运行）" }

$auths = @()
if ($token) {
  $auths += @{ Name = 'Bearer(密钥)'; Headers = @{ Authorization = "Bearer $token" } }
  $auths += @{ Name = 'Cookie'; Headers = @{ Cookie = $token } }
} else {
  $auths += @{ Name = '无凭据'; Headers = @{ } }
}

$urls = @(
  'https://vibetoken.top/v1/dashboard/billing/credit_grants',
  'https://vibetoken.top/v1/dashboard/billing/subscription',
  'https://vibetoken.top/v1/usage',
  'https://vibetoken.top/v1/me',
  'https://vibetoken.top/dashboard/billing/credit_grants',
  'https://vibetoken.top/api/balance',
  'https://vibetoken.top/api/user/balance',
  'https://vibetoken.top/v1/user/balance',
  'https://vibetoken.top/user/balance'
)

foreach ($u in $urls) {
  "`n===== $u ====="
  foreach ($a in $auths) {
    try {
      $r = Invoke-WebRequest -Uri $u -Headers $a.Headers -UseBasicParsing -TimeoutSec 20
      "  [$($a.Name)] 状态: $($r.StatusCode)  类型: $($r.Headers['Content-Type'])"
      $s = $r.Content
      if ($s.Length -gt 500) { $s = $s.Substring(0, 500) + ' ...(截断)' }
      "    " + (($s -replace '\s+', ' ').Trim())
    } catch {
      $resp = $_.Exception.Response
      if ($resp) {
        "  [$($a.Name)] 状态: $([int]$resp.StatusCode) $($resp.StatusDescription)"
        try {
          $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
          $s = $sr.ReadToEnd()
          if ($s.Length -gt 500) { $s = $s.Substring(0, 500) + ' ...(截断)' }
          "    " + (($s -replace '\s+', ' ').Trim())
        } catch { }
      } else {
        "  [$($a.Name)] 错误: $($_.Exception.Message)"
      }
    }
  }
}

"`n完成。请把以上输出完整复制发给作者。"
