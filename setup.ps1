# ============================================================================
#  余额挂件 - 配置向导（面向零基础用户的图形化配置工具）
#
#  用法：双击 配置向导.vbs（或 配置向导.bat）
#  流程：选平台 → 粘贴 API 密钥 → 自动检测接口 → 保存并启动
#
#  测试：
#    powershell -File setup.ps1 -SmokeTest -ConfigPath <临时配置文件>
# ============================================================================
param(
  [string]$ConfigPath = '',
  [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$script:scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($ConfigPath) { $script:configPath = $ConfigPath }
else { $script:configPath = Join-Path $script:scriptDir 'config.json' }

# ---------- 平台预设 ----------
$script:presets = @(
  @{ Name = 'DeepSeek（官方）';   Block = 'deepseek';   OpenUrl = 'https://platform.deepseek.com/usage';            ApiUrl = 'https://api.deepseek.com/user/balance'; Auth = 'bearer'; Mode = 'deepseek'; JsonPath = ''; ExtraPath = ''; Divisor = 1; Currency = '¥'; Accent = '#4D6BFE'; NeedBase = $false; BaseHint = '' },
  @{ Name = 'VibeToken';          Block = 'vibetoken';  OpenUrl = 'https://vibetoken.top/dashboard';                ApiUrl = 'https://vibetoken.top/v1/usage';       Auth = 'bearer'; Mode = 'jsonpath'; JsonPath = 'balance'; ExtraPath = 'usage.total.actual_cost'; Divisor = 1; Currency = '$'; Accent = '#A78BFA'; NeedBase = $false; BaseHint = '' },
  @{ Name = 'OpenRouter';         Block = 'openrouter'; OpenUrl = 'https://openrouter.ai/settings/keys';            ApiUrl = 'https://openrouter.ai/api/v1/auth/key'; Auth = 'bearer'; Mode = 'jsonpath'; JsonPath = 'data.limit'; ExtraPath = 'data.usage'; Divisor = 1; Currency = '$'; Accent = '#FF6600'; NeedBase = $false; BaseHint = '' },
  @{ Name = 'OpenAI 兼容中转站（通用）'; Block = '';    OpenUrl = '';                                              ApiUrl = '{BASE}/v1/usage';                       Auth = 'bearer'; Mode = 'jsonpath'; JsonPath = 'balance'; ExtraPath = ''; Divisor = 1; Currency = '$'; Accent = '#22C55E'; NeedBase = $true; BaseHint = 'https://你的中转站地址' },
  @{ Name = 'new-api 中转站（需要 Cookie）'; Block = ''; OpenUrl = '';                                            ApiUrl = '{BASE}/api/user/self';                  Auth = 'cookie'; Mode = 'newapi'; JsonPath = ''; ExtraPath = ''; Divisor = 1; Currency = '$'; Accent = '#22C55E'; NeedBase = $true; BaseHint = 'https://你的中转站地址' },
  @{ Name = '自定义（高级用户）';  Block = 'custom';     OpenUrl = '';                                              ApiUrl = '';                                      Auth = 'bearer'; Mode = 'jsonpath'; JsonPath = 'balance'; ExtraPath = ''; Divisor = 1; Currency = '$'; Accent = '#94A3B8'; NeedBase = $false; BaseHint = '' }
)

# ---------- 接口自动检测脚本（独立 Runspace 中执行，不卡界面） ----------
$script:detectScript = @'
param($Key, $Base)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http
function Try-Url($url, $needFields) {
  try {
    $handler = New-Object System.Net.Http.HttpClientHandler
    if ($env:WIDGET_NO_PROXY -eq '1') { $handler.UseProxy = $false }
    $handler.UseCookies = $false
    $client = New-Object System.Net.Http.HttpClient $handler
    $client.Timeout = [TimeSpan]::FromSeconds(8)
    $req = New-Object System.Net.Http.HttpRequestMessage('GET', $url)
    $null = $req.Headers.TryAddWithoutValidation('Authorization', "Bearer $Key")
    $resp = $client.SendAsync($req).GetAwaiter().GetResult()
    $code = [int]$resp.StatusCode
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $client.Dispose()
    if ($code -ne 200) { return $null }
    $j = $body | ConvertFrom-Json
    $found = $null
    foreach ($f in $needFields) {
      $cur = $j; $ok = $true
      foreach ($seg in ($f -split '\.')) {
        if ($null -eq $cur -or $null -eq $cur.$seg) { $ok = $false; break }
        $cur = $cur.$seg
      }
      if ($ok) { $found = $f; break }
    }
    if (-not $found) { return $null }
    return @{ Url = $url; Field = $found; Json = ($j | ConvertTo-Json -Depth 6 -Compress) }
  } catch { return $null }
}
$cands = @()
if ($Key -like 'sk-or-*') {
  $cands += @{ Url = 'https://openrouter.ai/api/v1/auth/key'; Fields = @('data.limit','data.usage'); Mode = 'jsonpath'; Main = 'data.limit'; Extra = 'data.usage' }
}
$cands += @{ Url = 'https://api.deepseek.com/user/balance'; Fields = @('balance_infos'); Mode = 'deepseek'; Main = ''; Extra = '' }
if ($Base) {
  $base = "$Base".TrimEnd('/')
  $cands += @{ Url = "$base/v1/usage"; Fields = @('balance','remaining'); Mode = 'jsonpath'; Main = 'balance'; Extra = 'usage.total.actual_cost' }
  $cands += @{ Url = "$base/v1/dashboard/billing/credit_grants"; Fields = @('total_available'); Mode = 'jsonpath'; Main = 'total_available'; Extra = 'total_used' }
  $cands += @{ Url = "$base/api/user/self"; Fields = @('data.quota'); Mode = 'newapi'; Main = ''; Extra = '' }
}
$found = $null
foreach ($c in $cands) {
  $r = Try-Url $c.Url $c.Fields
  if ($r) {
    $found = [pscustomobject]@{ Url = $r.Url; Field = $r.Field; Mode = $c.Mode; Main = $c.Main; Extra = $c.Extra; Json = $r.Json }
    break
  }
}
if ($found) { $found | ConvertTo-Json -Depth 6 -Compress } else { 'NULL' }
'@

# ---------- 写配置 + 生成启动器 ----------
function Save-SiteConfig([string]$block, [hashtable]$f) {
  if (-not (Test-Path $script:configPath)) {
    Set-Content -Path $script:configPath -Value '{}' -Encoding UTF8
  }
  $cfg = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $blockObj = [pscustomobject]@{
    title          = $f['title']
    openUrl        = $f['openUrl']
    apiUrl         = $f['apiUrl']
    auth           = $f['auth']
    token          = $f['token']
    mode           = $f['mode']
    jsonPath       = $f['jsonPath']
    extraPath      = $f['extraPath']
    quotaPerUnit   = 500000
    divisor        = $f['divisor']
    currency       = $f['currency']
    refreshSeconds = 300
    accent         = $f['accent']
    x              = 60
    y              = 60
    docked         = $false
    dockEdge       = 'left'
  }
  $cfg | Add-Member -NotePropertyName $block -NotePropertyValue $blockObj -Force
  $cfg | ConvertTo-Json -Depth 8 | Set-Content -Path $script:configPath -Encoding UTF8
  # 生成对应启动器（若不存在）：start-<block>.vbs
  $vbsPath = Join-Path $script:scriptDir "start-$block.vbs"
  if (-not (Test-Path $vbsPath)) {
    $vbs = @'
Set ws = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
site = Replace(Replace(WScript.ScriptName, "start-", ""), ".vbs", "")
ws.Environment("Process")("WIDGET_NO_CONSOLE") = "1"
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "balance-widget.ps1"" -Site " & site, 0, False
'@
    [IO.File]::WriteAllText($vbsPath, $vbs, (New-Object System.Text.ASCIIEncoding))
  }
  return $vbsPath
}

# ---------- 冒烟测试：自动执行一次保存后关闭 ----------
if ($SmokeTest) {
  $preset = $script:presets[0]
  $vbs = Save-SiteConfig 'deepseek' @{
    title = $preset.Name; openUrl = $preset.OpenUrl; apiUrl = $preset.ApiUrl; auth = $preset.Auth
    token = 'sk-test'; mode = $preset.Mode; jsonPath = $preset.JsonPath; extraPath = $preset.ExtraPath
    divisor = $preset.Divisor; currency = $preset.Currency; accent = $preset.Accent
  }
  "SMOKE-SAVED: $script:configPath"
  "SMOKE-VBS: $vbs"
  exit 0
}

# ---------- WPF 界面 ----------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="余额挂件配置向导" Width="560" Height="600" WindowStartupLocation="CenterScreen"
        FontFamily="Microsoft YaHei UI" Background="#F5F6FA" ResizeMode="NoResize">
  <ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="22,18,22,18">
    <TextBlock Text="余额挂件 · 配置向导" FontSize="19" FontWeight="Bold" Foreground="#1F2937"/>
    <TextBlock Text="选平台 → 粘贴密钥 → 自动检测 → 保存，三步搞定，不用碰任何文件" FontSize="11" Foreground="#6B7280" Margin="0,3,0,14" TextWrapping="Wrap"/>

    <TextBlock Text="1. 选择平台" FontSize="12" FontWeight="SemiBold" Foreground="#374151"/>
    <ComboBox x:Name="PresetBox" Margin="0,4,0,10" Padding="6,4"/>

    <TextBlock x:Name="BaseLabel" Text="站点地址（如 https://api.xxx.com）" FontSize="12" FontWeight="SemiBold" Foreground="#374151" Visibility="Collapsed"/>
    <TextBox x:Name="BaseBox" Margin="0,4,0,10" Padding="6,4" Visibility="Collapsed"/>

    <TextBlock Text="2. 粘贴 API 密钥（sk-…）或 Cookie" FontSize="12" FontWeight="SemiBold" Foreground="#374151"/>
    <TextBox x:Name="KeyBox" Margin="0,4,0,4" Padding="6,4"/>
    <TextBlock Text="密钥一般在平台的「API Keys / 令牌」页面创建。DeepSeek/中转站是 sk- 开头，OpenRouter 是 sk-or- 开头；Cookie 形如 session=xxx。" FontSize="10" Foreground="#9CA3AF" TextWrapping="Wrap"/>

    <Button x:Name="DetectBtn" Content="🔍 自动检测接口（推荐）" Margin="0,12,0,0" Padding="12,7" HorizontalAlignment="Left" Background="#F3F4F6" BorderBrush="#D1D5DB"/>
    <TextBlock x:Name="DetectStatus" FontSize="11" Foreground="#6B7280" Margin="0,6,0,0" TextWrapping="Wrap"/>

    <TextBlock Text="3. 高级设置（自动填好，一般不用改）" FontSize="12" FontWeight="SemiBold" Foreground="#374151" Margin="0,14,0,4"/>
    <Grid Margin="0,4,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="82"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="70"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Grid.Column="0" Text="接口地址" VerticalAlignment="Center" FontSize="11" Foreground="#6B7280"/>
      <TextBox x:Name="ApiUrlBox" Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="3" Margin="0,0,0,6" Padding="5,3" FontSize="11"/>
      <TextBlock Grid.Row="1" Grid.Column="0" Text="认证方式" VerticalAlignment="Center" FontSize="11" Foreground="#6B7280"/>
      <ComboBox x:Name="AuthBox" Grid.Row="1" Grid.Column="1" Margin="0,0,6,6" Padding="5,2" FontSize="11"/>
      <TextBlock Grid.Row="1" Grid.Column="2" Text="货币符号" VerticalAlignment="Center" FontSize="11" Foreground="#6B7280"/>
      <TextBox x:Name="CurrencyBox" Grid.Row="1" Grid.Column="3" Margin="0,0,0,6" Padding="5,3" FontSize="11"/>
      <TextBlock Grid.Row="2" Grid.Column="0" Text="余额字段" VerticalAlignment="Center" FontSize="11" Foreground="#6B7280"/>
      <TextBox x:Name="JsonPathBox" Grid.Row="2" Grid.Column="1" Margin="0,0,6,0" Padding="5,3" FontSize="11"/>
      <TextBlock Grid.Row="2" Grid.Column="2" Text="已用字段" VerticalAlignment="Center" FontSize="11" Foreground="#6B7280"/>
      <TextBox x:Name="ExtraPathBox" Grid.Row="2" Grid.Column="3" Margin="0,0,0,0" Padding="5,3" FontSize="11"/>
    </Grid>

    <CheckBox x:Name="AutoStartChk" Content="保存后立即启动挂件" IsChecked="True" Margin="0,14,0,0"/>
    <Button x:Name="SaveBtn" Content="保 存 并 启 动" FontSize="14" FontWeight="Bold" Padding="16,9" HorizontalAlignment="Left" Margin="0,10,0,0" Background="#2563EB" Foreground="White" BorderThickness="0"/>
    <TextBlock x:Name="StatusText" FontSize="11" Margin="0,10,0,0" TextWrapping="Wrap" Foreground="#374151"/>
  </StackPanel>
  </ScrollViewer>
</Window>
'@

$window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
$PresetBox     = $window.FindName('PresetBox')
$BaseLabel     = $window.FindName('BaseLabel')
$BaseBox       = $window.FindName('BaseBox')
$KeyBox        = $window.FindName('KeyBox')
$DetectBtn     = $window.FindName('DetectBtn')
$DetectStatus  = $window.FindName('DetectStatus')
$ApiUrlBox     = $window.FindName('ApiUrlBox')
$AuthBox       = $window.FindName('AuthBox')
$CurrencyBox   = $window.FindName('CurrencyBox')
$JsonPathBox   = $window.FindName('JsonPathBox')
$ExtraPathBox  = $window.FindName('ExtraPathBox')
$AutoStartChk  = $window.FindName('AutoStartChk')
$SaveBtn       = $window.FindName('SaveBtn')
$StatusText    = $window.FindName('StatusText')

# ---------- 状态函数 ----------
function Set-Status([string]$text, [string]$color) {
  $StatusText.Text = $text
  $StatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color))
}

# ---------- 预设选择 ----------
foreach ($p in $script:presets) { $null = $PresetBox.Items.Add($p.Name) }
$PresetBox.SelectedIndex = 0
function Apply-Preset {
  $idx = $PresetBox.SelectedIndex
  if ($idx -lt 0) { return }
  $p = $script:presets[$idx]
  $needBase = [bool]$p.NeedBase
  $BaseLabel.Visibility = if ($needBase) { 'Visible' } else { 'Collapsed' }
  $BaseBox.Visibility   = if ($needBase) { 'Visible' } else { 'Collapsed' }
  $AuthBox.Items.Clear()
  foreach ($a in @('bearer', 'cookie')) { $null = $AuthBox.Items.Add($a) }
  $AuthBox.SelectedItem = $p.Auth
  $CurrencyBox.Text = $p.Currency
  $JsonPathBox.Text = $p.JsonPath
  $ExtraPathBox.Text = $p.ExtraPath
  $ApiUrlBox.Text = if ($needBase) { $p.ApiUrl } else { $p.ApiUrl }
  $DetectStatus.Text = ''
}
$PresetBox.Add_SelectionChanged({
  Apply-Preset
})
Apply-Preset

# ---------- 自动检测（独立 Runspace + 轮询） ----------
$script:detectPs = $null
$script:detectHandle = $null
$DetectBtn.Add_Click({
  $key = $KeyBox.Text.Trim()
  if (-not $key) { Set-Status '请先粘贴 API 密钥' '#DC2626'; return }
  $base = $BaseBox.Text.Trim()
  if ($BaseBox.Visibility -eq 'Visible' -and -not $base) { Set-Status '请填写站点地址，例如 https://api.你的站点.com' '#DC2626'; return }
  $DetectStatus.Text = '正在检测常见接口，请稍候…'
  $DetectBtn.IsEnabled = $false
  try {
    $script:detectPs = [powershell]::Create()
    $null = $script:detectPs.AddScript($script:detectScript)
    $null = $script:detectPs.AddArgument($key)
    $null = $script:detectPs.AddArgument($base)
    $script:detectHandle = $script:detectPs.BeginInvoke()
  } catch {
    $DetectBtn.IsEnabled = $true
    Set-Status "检测启动失败：$($_.Exception.Message)" '#DC2626'
  }
})
$pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$pollTimer.Add_Tick({
  if (-not $script:detectHandle) { return }
  if (-not $script:detectHandle.IsCompleted) { return }
  $json = $null
  try { $json = $script:detectPs.EndInvoke($script:detectHandle) | Select-Object -First 1 } catch { }
  try { $script:detectPs.Dispose() } catch { }
  $script:detectPs = $null
  $script:detectHandle = $null
  $DetectBtn.IsEnabled = $true
  if (-not $json -or "$json" -eq 'NULL') {
    Set-Status '未检测到可用接口。请检查密钥是否正确、站点地址是否可访问；或手动填写高级设置。' '#DC2626'
    return
  }
  try {
    $r = $json | ConvertFrom-Json
    $ApiUrlBox.Text = $r.Url
    if ($r.Mode) {
      $AuthBox.SelectedItem = 'bearer'
      $JsonPathBox.Text = "$($r.Main)"
      $ExtraPathBox.Text = "$($r.Extra)"
    }
    Set-Status "检测成功：接口 $($r.Url)（命中字段 $($r.Field)）。可直接保存。" '#16A34A'
  } catch {
    Set-Status "检测结果解析失败：$($_.Exception.Message)" '#DC2626'
  }
})
$pollTimer.Start()

# ---------- 保存 ----------
$SaveBtn.Add_Click({
  $key = $KeyBox.Text.Trim()
  if (-not $key) { Set-Status '请先粘贴 API 密钥或 Cookie' '#DC2626'; return }
  $idx = $PresetBox.SelectedIndex
  if ($idx -lt 0) { Set-Status '请先选择平台' '#DC2626'; return }
  $p = $script:presets[$idx]
  $apiUrl = $ApiUrlBox.Text.Trim()
  if (-not $apiUrl) { Set-Status '接口地址为空（可点「自动检测」或手动填写）' '#DC2626'; return }
  # 配置块名
  $block = "$($p.Block)"
  if (-not $block) {
    $base = $BaseBox.Text.Trim()
    $block = ($base -replace '^https?://', '') -split '[/.]' | Where-Object { $_ } | Select-Object -First 1
    if (-not $block) { $block = 'custom' }
  }
  $openUrl = "$($p.OpenUrl)"
  if (-not $openUrl -and $BaseBox.Text.Trim()) { $openUrl = $BaseBox.Text.Trim().TrimEnd('/') + '/dashboard' }
  $title = $p.Name -replace '（.*', ''
  try {
    $vbs = Save-SiteConfig $block @{
      title = $title; openUrl = $openUrl; apiUrl = $apiUrl
      auth = "$($AuthBox.SelectedItem)"; token = $key
      mode = "$($p.Mode)"; jsonPath = $JsonPathBox.Text.Trim(); extraPath = $ExtraPathBox.Text.Trim()
      divisor = 1; currency = $CurrencyBox.Text.Trim(); accent = $p.Accent
    }
    $msg = "已保存到 config.json（平台：$block）。启动器：start-$block.vbs"
    Set-Status $msg '#16A34A'
    if ($AutoStartChk.IsChecked) {
      Start-Process "$env:WINDIR\System32\wscript.exe" -ArgumentList "`"$vbs`"" | Out-Null
      Set-Status "$msg`n挂件已启动！以后双击 start-$block.vbs 即可再次打开。" '#16A34A'
    } else {
      Set-Status "$msg`n双击 start-$block.vbs 即可启动挂件。" '#16A34A'
    }
  } catch {
    Set-Status "保存失败：$($_.Exception.Message)" '#DC2626'
  }
})

# ---------- 运行 ----------
$window.Add_Closed({
  try { if ($script:detectHandle -and -not $script:detectHandle.IsCompleted) { $script:detectPs.Stop() } } catch { }
  try { if ($script:detectPs) { $script:detectPs.Dispose() } } catch { }
})
$app = New-Object System.Windows.Application
$app.Run($window) | Out-Null
