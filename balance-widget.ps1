# ============================================================================
#  余额挂件 balance-widget.ps1
#
#  把 DeepSeek / VibeToken 的 API 余额显示在桌面透明小卡片上：
#    - 单击卡片  -> 打开对应网页（充值 / 查看）
#    - 按住拖动  -> 移动位置（自动记住，重启后仍在原位）
#    - 右键      -> 刷新 / 复制余额 / 打开网页 / 开机自启 / 编辑配置 / 退出
#    - 定时刷新  -> 默认每 5 分钟（config.json 里 refreshSeconds 可改）
#
#  用法：
#    powershell -NoProfile -ExecutionPolicy Bypass -File balance-widget.ps1 -Site deepseek
#    powershell -NoProfile -ExecutionPolicy Bypass -File balance-widget.ps1 -Site vibetoken
#  测试：
#    powershell -NoProfile -ExecutionPolicy Bypass -File balance-widget.ps1 -Site deepseek -SmokeTest
# ============================================================================
param(
  [string]$Site = '',
  [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$script:scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:scriptPath = $MyInvocation.MyCommand.Path
$script:configPath = Join-Path $script:scriptDir 'config.json'
$script:errorLog   = Join-Path $script:scriptDir 'widget-error.log'

$script:defaultConfig = @'
{
  "deepseek": {
    "title": "DeepSeek API",
    "openUrl": "https://platform.deepseek.com/usage",
    "apiUrl": "https://api.deepseek.com/user/balance",
    "auth": "bearer",
    "token": "",
    "refreshSeconds": 300,
    "accent": "#4D6BFE",
    "x": 60,
    "y": 60,
    "docked": false,
    "dockEdge": "left"
  },
  "vibetoken": {
    "title": "VibeToken",
    "openUrl": "https://vibetoken.top/dashboard",
    "apiUrl": "https://vibetoken.top/v1/usage",
    "auth": "bearer",
    "token": "",
    "mode": "jsonpath",
    "jsonPath": "balance",
    "extraPath": "usage.total.actual_cost",
    "quotaPerUnit": 500000,
    "divisor": 1,
    "currency": "$",
    "refreshSeconds": 300,
    "accent": "#A78BFA",
    "x": 330,
    "y": 60,
    "docked": false,
    "dockEdge": "left"
  }
}
'@

function Read-Config {
  if (-not (Test-Path $script:configPath)) {
    Set-Content -Path $script:configPath -Value $script:defaultConfig -Encoding UTF8
    $script:configJustCreated = $true
  }
  Get-Content -Path $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-JsonPath($obj, $path) {
  $cur = $obj
  foreach ($seg in ($path -split '\.')) {
    if ($null -eq $cur) { return $null }
    $cur = $cur.$seg
  }
  return $cur
}

function Ensure-Prop($obj, $name, $default) {
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p -or [string]::IsNullOrEmpty("$($p.Value)")) {
    $obj | Add-Member -NotePropertyName $name -NotePropertyValue $default -Force
  }
}

function Main {
  Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
  Add-Type -AssemblyName System.Net.Http
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WndHelper {
    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out WndPoint lpPoint);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
public struct WndPoint {
    public int X;
    public int Y;
}
'@

  # ---------- 静默启动：由 start-*.vbs 启动器设置 WIDGET_NO_CONSOLE=1，隐藏控制台窗口 ----------
  if ($env:WIDGET_NO_CONSOLE -eq '1') {
    try {
      $ch = [WndHelper]::GetConsoleWindow()
      if ($ch -ne [IntPtr]::Zero) { [WndHelper]::ShowWindow($ch, 0) | Out-Null }
    } catch { }
  }

  # ---------- 站点选择 ----------
  # 支持任意平台：-Site 名称只要在 config.json 里有对应配置即可（不再限定 deepseek/vibetoken）
  if (-not $Site) {
    $c0 = Read-Config
    if ($c0.deepseek.token) { $script:Site = 'deepseek' }
    elseif ($c0.vibetoken.token) { $script:Site = 'vibetoken' }
    else { throw '未指定 -Site（如 deepseek / vibetoken / 自定义平台名），且 config.json 里还没有任何 Token' }
  } else { $script:Site = $Site }

  $cfg = Read-Config
  $sc = $cfg.$script:Site
  if (-not $sc) { throw "config.json 中缺少站点 $script:Site 的配置" }
  Ensure-Prop $sc 'title' $script:Site
  Ensure-Prop $sc 'accent' $(if ($script:Site -eq 'deepseek') { '#4D6BFE' } else { '#A78BFA' })
  Ensure-Prop $sc 'refreshSeconds' 300
  Ensure-Prop $sc 'quotaPerUnit' 500000
  Ensure-Prop $sc 'divisor' 500000
  Ensure-Prop $sc 'currency' '$'
  Ensure-Prop $sc 'docked' $false
  Ensure-Prop $sc 'dockEdge' 'left'
  $script:cfg = $cfg
  $script:siteCfg = $sc

  # ---------- 界面 XAML ----------
  $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="余额挂件" Width="262" Height="104" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ResizeMode="NoResize" ShowActivated="False"
        FontFamily="Microsoft YaHei UI" UseLayoutRounding="True"
        WindowStartupLocation="Manual">
  <Grid Margin="8">
    <Border x:Name="Card" CornerRadius="15" Background="#E610141C" BorderBrush="#3DFFFFFF" BorderThickness="1">
      <Border.Effect>
        <DropShadowEffect Color="#000000" BlurRadius="22" ShadowDepth="2" Opacity="0.5"/>
      </Border.Effect>
      <Grid Margin="14,9,14,9">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="Dot" Width="8" Height="8" VerticalAlignment="Center" Margin="0,0,7,0" Fill="#4ADE80"/>
            <TextBlock x:Name="TitleText" Text="余额挂件" FontSize="12" FontWeight="SemiBold" Foreground="#E6FFFFFF" VerticalAlignment="Center"/>
          </StackPanel>
          <TextBlock x:Name="HintText" Grid.Column="1" Text="点击充值 →" FontSize="10" Foreground="#7DFFFFFF" VerticalAlignment="Center"/>
        </Grid>
        <TextBlock x:Name="BalanceText" Grid.Row="1" Text="--" FontSize="27" FontWeight="Bold" Foreground="White" Margin="0,3,0,0"/>
        <TextBlock x:Name="StatusText" Grid.Row="2" Text="正在获取余额…" FontSize="10" Foreground="#99FFFFFF" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
      </Grid>
    </Border>
    <Border x:Name="Pill" Width="64" Height="24" CornerRadius="12" Background="#E610141C" BorderBrush="#3DFFFFFF" BorderThickness="1" Visibility="Collapsed" VerticalAlignment="Center">
      <Border.Effect>
        <DropShadowEffect Color="#000000" BlurRadius="14" ShadowDepth="1" Opacity="0.4"/>
      </Border.Effect>
      <TextBlock x:Name="PillText" Text="--" FontSize="10" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="6,0"/>
    </Border>
  </Grid>
</Window>
'@

  $window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
  $Card        = $window.FindName('Card')
  $Dot         = $window.FindName('Dot')
  $TitleText   = $window.FindName('TitleText')
  $HintText    = $window.FindName('HintText')
  $BalanceText = $window.FindName('BalanceText')
  $StatusText  = $window.FindName('StatusText')
  $Pill        = $window.FindName('Pill')
  $PillText    = $window.FindName('PillText')
  $script:ui   = $window.Dispatcher

  $TitleText.Text = $sc.title
  $Dot.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($sc.accent))
  $window.Left = if ($null -ne $sc.x) { [double]$sc.x } else { 60 }
  $window.Top  = if ($null -ne $sc.y) { [double]$sc.y } else { 60 }
  $script:docked = [bool]$sc.docked
  $script:dockEdge = "$($sc.dockEdge)"

  # 不在 Alt+Tab 列表里显示（工具窗口）
  $window.Add_SourceInitialized({
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    $ex = [WndHelper]::GetWindowLong($hwnd, -20)
    [WndHelper]::SetWindowLong($hwnd, -20, ($ex -bor 0x80)) | Out-Null
  })

  # 启动时若上次处于贴边状态，直接以角标形式出现
  $window.Add_Loaded({
    if ($script:docked) { Collapse-Pill $script:dockEdge }
    # 首次运行（配置文件刚生成、还没有任何密钥）→ 自动打开配置向导
    if ($script:configJustCreated -and -not $SmokeTest) {
      try {
        $wiz = Join-Path $script:scriptDir '配置向导.vbs'
        if (Test-Path $wiz) { Start-Process "$env:WINDIR\System32\wscript.exe" -ArgumentList "`"$wiz`"" }
      } catch { }
    }
  })

  # ---------- 界面小工具 ----------
  function Set-Dot([string]$hex) {
    $Dot.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
  }
  function Show-Status([string]$text, [string]$kind) {
    $hex = switch ($kind) {
      'err'  { '#F0716F' }
      'warn' { '#F5C26B' }
      default { '#99FFFFFF' }
    }
    $StatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
    $StatusText.Text = $text
  }
  function Save-Position {
    try {
      $c = Read-Config
      $c.$script:Site.x = [int][Math]::Round($window.Left)
      $c.$script:Site.y = [int][Math]::Round($window.Top)
      $c.$script:Site | Add-Member -NotePropertyName docked -NotePropertyValue ([bool]$script:docked) -Force
      $c.$script:Site | Add-Member -NotePropertyName dockEdge -NotePropertyValue "$($script:dockEdge)" -Force
      $c | ConvertTo-Json -Depth 8 | Set-Content -Path $script:configPath -Encoding UTF8
    } catch { }
  }
  function Ensure-Launchers {
    # 静默启动器（vbs，无任何控制台窗口），缺失时自动生成。
    # 站点名取自启动器文件名：把 start-deepseek.vbs 复制成 start-你的平台.vbs 即可启动对应平台。
    try {
      $vbsOne = @'
Set ws = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
site = Replace(Replace(WScript.ScriptName, "start-", ""), ".vbs", "")
ws.Environment("Process")("WIDGET_NO_CONSOLE") = "1"
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "balance-widget.ps1"" -Site " & site, 0, False
'@
      $vbsAll = @'
Set ws = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
ws.Run "wscript.exe """ & base & "start-deepseek.vbs""", 0, False
ws.Run "wscript.exe """ & base & "start-vibetoken.vbs""", 0, False
'@
      $map = @{
        'start-deepseek.vbs' = $vbsOne
        'start-vibetoken.vbs' = $vbsOne
        'start-all.vbs' = $vbsAll
      }
      foreach ($name in $map.Keys) {
        $p = Join-Path $script:scriptDir $name
        if (-not (Test-Path $p)) {
          [IO.File]::WriteAllText($p, $map[$name], (New-Object System.Text.ASCIIEncoding))
        }
      }
    } catch { }
  }
  function Set-AutoStart([bool]$on) {
    $lnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) "余额挂件-$($script:Site).lnk"
    if ($on) {
      Ensure-Launchers
      $ws = New-Object -ComObject WScript.Shell
      $lnk = $ws.CreateShortcut($lnkPath)
      $lnk.TargetPath = "$env:WINDIR\System32\wscript.exe"
      $lnk.Arguments = "`"$(Join-Path $script:scriptDir "start-$($script:Site).vbs")`""
      $lnk.WorkingDirectory = $script:scriptDir
      $lnk.Description = "余额挂件 - $($script:Site)"
      $lnk.Save()
    } else {
      Remove-Item $lnkPath -Force -ErrorAction SilentlyContinue
    }
  }
  function Test-AutoStart {
    Test-Path (Join-Path ([Environment]::GetFolderPath('Startup')) "余额挂件-$($script:Site).lnk")
  }

  # ---------- 余额获取（独立 Runspace 异步执行，不卡界面） ----------
  # 注意：不能在线程池线程里跑 PowerShell 脚本块（会与主运行空间死锁），
  # 所以 HTTP 请求放到独立 Runspace，UI 线程用 1 秒定时器轮询结果。
  $script:fetchScript = @'
param($ApiUrl, $Auth, $Token)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http
try {
  $handler = New-Object System.Net.Http.HttpClientHandler
  if ($env:WIDGET_NO_PROXY -eq '1') { $handler.UseProxy = $false }
  $handler.UseCookies = $false
  $client = New-Object System.Net.Http.HttpClient $handler
  $client.Timeout = [TimeSpan]::FromSeconds(20)
  $req = New-Object System.Net.Http.HttpRequestMessage('GET', $ApiUrl)
  if ($Auth -eq 'cookie') {
    $null = $req.Headers.TryAddWithoutValidation('Cookie', $Token)
  } else {
    $t = $Token
    if ($t -like 'Bearer *') { $t = $t.Substring(7).Trim() }
    $null = $req.Headers.TryAddWithoutValidation('Authorization', "Bearer $t")
  }
  $resp = $client.SendAsync($req).GetAwaiter().GetResult()
  $code = [int]$resp.StatusCode
  $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  $client.Dispose()
  if ($code -eq 200) {
    $r = $body | ConvertFrom-Json
    [pscustomobject]@{ Ok = $true; Code = 200; Err = ''; Json = ($r | ConvertTo-Json -Depth 8 -Compress) }
  } else {
    [pscustomobject]@{ Ok = $false; Code = $code; Err = "HTTP $code"; Json = '' }
  }
} catch {
  [pscustomobject]@{ Ok = $false; Code = 0; Err = $_.Exception.GetBaseException().Message; Json = '' }
}
'@
  $script:fetchPs = $null
  $script:fetchHandle = $null
  $script:fetchStarted = $null

  function Handle-Response([int]$code, [string]$body, [string]$err) {
    if ($err) {
      Show-Status "获取失败：$err" 'err'
      Set-Dot '#F0716F'
      return
    }
    if ($code -eq 401 -or $code -eq 403) {
      Show-Status '密钥/登录已失效：单击打开网页重新获取' 'err'
      Set-Dot '#F0716F'
      return
    }
    if ($code -ne 200) {
      Show-Status "接口返回 HTTP $code" 'err'
      Set-Dot '#F0716F'
      return
    }
    try {
      $j = $body | ConvertFrom-Json
      $main = ''; $sub = ''; $tip = ''
      if ($script:Site -eq 'deepseek') {
        # 官方接口：{ "is_available": true, "balance_infos": [ { currency, total_balance, granted_balance, topped_up_balance } ] }
        $infos = @($j.balance_infos | Where-Object { $_ })
        if ($infos.Count -eq 0) { Show-Status '接口未返回余额信息' 'warn'; Set-Dot '#F5C26B'; return }
        $lines = @()
        foreach ($info in $infos) {
          $sym = if ($info.currency -eq 'CNY') { '¥' } elseif ($info.currency -eq 'USD') { '$' } else { "$($info.currency) " }
          $lines += "$($info.currency)：总额 $sym$($info.total_balance)（赠送 $sym$($info.granted_balance) / 充值 $sym$($info.topped_up_balance)）"
        }
        $i0 = $infos[0]
        $s0 = if ($i0.currency -eq 'CNY') { '¥' } elseif ($i0.currency -eq 'USD') { '$' } else { "$($i0.currency) " }
        $main = "$s0$($i0.total_balance)"
        $sub = "赠送 $s0$($i0.granted_balance) · 充值 $s0$($i0.topped_up_balance)"
        $tip = $lines -join "`n"
        if (-not $j.is_available) {
          $sub = '账户不可用（可能欠费）'
          $tip = "$tip`n账户当前不可用"
          Set-Dot '#F5C26B'
        }
      } else {
        # VibeToken：默认按 new-api/one-api 风格解析（/api/user/self 返回 data.quota）
        if ($script:siteCfg.mode -eq 'jsonpath') {
          $val = Get-JsonPath $j $script:siteCfg.jsonPath
          $extra = if ($script:siteCfg.extraPath) { Get-JsonPath $j $script:siteCfg.extraPath } else { $null }
          if ($null -eq $val) { Show-Status "找不到字段 $($script:siteCfg.jsonPath)" 'warn'; Set-Dot '#F5C26B'; return }
          $main = "$($script:siteCfg.currency) $('{0:N2}' -f ([double]$val / [double]$script:siteCfg.divisor))"
          if ($null -ne $extra) { $sub = "已用 $($script:siteCfg.currency) $('{0:N2}' -f ([double]$extra / [double]$script:siteCfg.divisor))" }
        } else {
          $d = $j.data
          if ($null -eq $d.quota) { Show-Status '接口返回里没有 quota 字段（站点可能不是 new-api 系，运行 probe-vibetoken.bat 探测）' 'warn'; Set-Dot '#F5C26B'; return }
          $main = "$($script:siteCfg.currency) $('{0:N2}' -f ([double]$d.quota / [double]$script:siteCfg.quotaPerUnit))"
          $sub = "已用 $($script:siteCfg.currency) $('{0:N2}' -f ([double]$d.used_quota / [double]$script:siteCfg.quotaPerUnit))"
          $tip = "剩余额度（原始单位）：$($d.quota)`n已用额度（原始单位）：$($d.used_quota)`n总请求数：$($d.request_count)"
          if ($null -ne $d.status -and $d.status -ne 1) { $sub = '账户状态异常，请到网页查看' }
        }
      }
      $script:lastUpdate = Get-Date -Format 'HH:mm:ss'
      $BalanceText.Text = $main
      $PillText.Text = ($main -replace ' ', '') -replace '(\.\d)\d*$', '$1'
      if ($sub) { $StatusText.Text = "$sub · 更新于 $($script:lastUpdate)" }
      else { $StatusText.Text = "更新于 $($script:lastUpdate)" }
      $StatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#99FFFFFF'))
      if ($tip) { $Card.ToolTip = $tip } else { $Card.ToolTip = $null }
      Set-Dot '#4ADE80'
    } catch {
      Show-Status "解析失败：$($_.Exception.Message)" 'err'
      Set-Dot '#F0716F'
    }
  }

  function Update-Balance {
    try { $script:siteCfg = (Read-Config).$script:Site } catch { }
    if (-not $script:siteCfg) { Show-Status '配置读取失败' 'err'; return }
    if (-not $script:siteCfg.apiUrl) { Show-Status '配置缺少 apiUrl：右键 → 编辑配置' 'warn'; return }
    $token = "$($script:siteCfg.token)".Trim()
    if (-not $token) {
      Show-Status '未配置 Token：右键 → 编辑配置' 'warn'
      Set-Dot '#F5C26B'
      return
    }
    Show-Status '获取中…' 'normal'
    # 上一次请求还没结束则忽略本次（防止堆积）
    if ($script:fetchHandle -and -not $script:fetchHandle.IsCompleted) { return }
    try {
      $script:fetchPs = [powershell]::Create()
      $null = $script:fetchPs.AddScript($script:fetchScript)
      $null = $script:fetchPs.AddArgument($script:siteCfg.apiUrl)
      $null = $script:fetchPs.AddArgument($script:siteCfg.auth)
      $null = $script:fetchPs.AddArgument($token)
      $script:fetchStarted = Get-Date
      $script:fetchHandle = $script:fetchPs.BeginInvoke()
    } catch {
      Show-Status "请求失败：$($_.Exception.Message)" 'err'
      Set-Dot '#F0716F'
    }
  }

  # ---------- 拖动 / 单击 ----------
  # 用 Win32 GetCursorPos 取绝对屏幕坐标（物理像素），再经 TransformFromDevice
  # 换算成 DIP 后移动窗口：避免 Mouse.GetPosition(null) 在缩放显示下坐标单位
  # 不一致导致的拖动变慢、以及相对坐标反馈回路导致的抖动。
  # 拖动期间临时去掉阴影，避免每帧重绘阴影造成卡顿。
  function Get-CursorDip {
    $wp = New-Object WndPoint
    [WndHelper]::GetCursorPos([ref]$wp) | Out-Null
    $pt = New-Object System.Windows.Point($wp.X, $wp.Y)
    $src = [System.Windows.PresentationSource]::FromVisual($window)
    if ($src -and $src.CompositionTarget) {
      return $src.CompositionTarget.TransformFromDevice.Transform($pt)
    }
    return $pt
  }

  # ---------- 贴边角标（悬浮球） ----------
  $script:cardW = 262; $script:cardH = 104
  $script:pillW = 80;  $script:pillH = 40
  $script:dockThreshold = 50
  $script:collapseTimer = New-Object System.Windows.Threading.DispatcherTimer
  # 收回延迟仅 150ms：过滤弹出/展开瞬间的误触发，手感上等于"一离开就缩回去"
  $script:collapseTimer.Interval = [TimeSpan]::FromMilliseconds(150)
  $script:collapseTimer.Add_Tick({
    $script:collapseTimer.Stop()
    if ($script:mouseDown) { return }
    if (-not $script:docked) { return }
    if ($Pill.Visibility -eq 'Visible') { return }
    if ($Card.ContextMenu.IsOpen -or $Pill.ContextMenu.IsOpen) { return }
    if (-not $window.IsMouseOver) {
      Collapse-Pill $script:dockEdge
      Save-Position
    }
  })
  function Get-WorkArea {
    $src = [System.Windows.PresentationSource]::FromVisual($window)
    if ($src -and $src.CompositionTarget) {
      $tf = $src.CompositionTarget.TransformFromDevice
      $toDev = $src.CompositionTarget.TransformToDevice
      $cx = $window.Left + $window.Width / 2
      $cy = $window.Top + $window.Height / 2
      $d = $toDev.Transform([System.Windows.Point]::new($cx, $cy))
      $screen = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new([int]$d.X, [int]$d.Y))
      $wa = $screen.WorkingArea
      $p1 = $tf.Transform([System.Windows.Point]::new($wa.X, $wa.Y))
      $p2 = $tf.Transform([System.Windows.Point]::new($wa.X + $wa.Width, $wa.Y + $wa.Height))
      return @{ Left = $p1.X; Top = $p1.Y; Right = $p2.X; Bottom = $p2.Y }
    }
    $wa2 = [System.Windows.SystemParameters]::WorkArea
    return @{ Left = $wa2.X; Top = $wa2.Y; Right = $wa2.X + $wa2.Width; Bottom = $wa2.Y + $wa2.Height }
  }
  function Find-Edge($cx, $cy, [bool]$force = $false) {
    $wa = Get-WorkArea
    $best = @(
      @{ Name = 'left';   Dist = [Math]::Abs($cx - $wa.Left) },
      @{ Name = 'right';  Dist = [Math]::Abs($cx - $wa.Right) },
      @{ Name = 'top';    Dist = [Math]::Abs($cy - $wa.Top) },
      @{ Name = 'bottom'; Dist = [Math]::Abs($cy - $wa.Bottom) }
    ) | Sort-Object { $_.Dist } | Select-Object -First 1
    if ($force) { return $best.Name }
    if ($best.Dist -le $script:dockThreshold) { return $best.Name }
    return $null
  }
  function Collapse-Pill([string]$edge) {
    $wa = Get-WorkArea
    $x = $window.Left; $y = $window.Top
    switch ($edge) {
      'left'   { $x = $wa.Left - 8; $y = [Math]::Max($wa.Top, [Math]::Min($y, $wa.Bottom - $script:pillH)) }
      'right'  { $x = $wa.Right - $script:pillW + 8; $y = [Math]::Max($wa.Top, [Math]::Min($y, $wa.Bottom - $script:pillH)) }
      'top'    { $y = $wa.Top - 8; $x = [Math]::Max($wa.Left, [Math]::Min($x, $wa.Right - $script:pillW)) }
      'bottom' { $y = $wa.Bottom - $script:pillH + 8; $x = [Math]::Max($wa.Left, [Math]::Min($x, $wa.Right - $script:pillW)) }
    }
    $Card.Visibility = 'Collapsed'
    $Pill.Visibility = 'Visible'
    $window.Width = $script:pillW
    $window.Height = $script:pillH
    $window.Left = $x
    $window.Top = $y
    $script:docked = $true
    $script:dockEdge = $edge
  }
  function Expand-Card([bool]$stayDocked, [string]$edge, [double]$cx, [double]$cy) {
    $wa = Get-WorkArea
    $x = $window.Left; $y = $window.Top
    if ($edge) {
      switch ($edge) {
        'left'   { $x = $wa.Left - 8; $y = [Math]::Max($wa.Top, [Math]::Min($y, $wa.Bottom - $script:cardH)) }
        'right'  { $x = $wa.Right - $script:cardW + 8; $y = [Math]::Max($wa.Top, [Math]::Min($y, $wa.Bottom - $script:cardH)) }
        'top'    { $y = $wa.Top - 8; $x = [Math]::Max($wa.Left, [Math]::Min($x, $wa.Right - $script:cardW)) }
        'bottom' { $y = $wa.Bottom - $script:cardH + 8; $x = [Math]::Max($wa.Left, [Math]::Min($x, $wa.Right - $script:cardW)) }
      }
    } else {
      $x = $cx - $script:cardW / 2
      $y = $cy - $script:cardH / 2
      $x = [Math]::Max($wa.Left, [Math]::Min($x, $wa.Right - $script:cardW))
      $y = [Math]::Max($wa.Top, [Math]::Min($y, $wa.Bottom - $script:cardH))
    }
    $Card.Visibility = 'Visible'
    $Pill.Visibility = 'Collapsed'
    $window.Width = $script:cardW
    $window.Height = $script:cardH
    $window.Left = $x
    $window.Top = $y
    $script:docked = $stayDocked
    if ($edge) { $script:dockEdge = $edge }
  }

  $script:mouseDown = $false; $script:hasMoved = $false
  $script:shadowEffect = $Card.Effect
  $script:pillShadow = $Pill.Effect
  $window.Add_MouseLeftButtonDown({
    $script:mouseDown = $true; $script:hasMoved = $false
    if ($Pill.Visibility -eq 'Visible') {
      # 从角标拉出：在角标位置展开成卡片，进入自由拖动
      $cx = $window.Left + $window.Width / 2
      $cy = $window.Top + $window.Height / 2
      Expand-Card $false $null $cx $cy
    }
    $script:downPos = Get-CursorDip
    $script:lastPos = $script:downPos
    $null = $window.CaptureMouse()
  })
  $window.Add_MouseMove({
    if (-not $script:mouseDown) { return }
    $p = Get-CursorDip
    if (-not $script:hasMoved) {
      if ([Math]::Abs($p.X - $script:downPos.X) -gt 3 -or [Math]::Abs($p.Y - $script:downPos.Y) -gt 3) {
        $script:hasMoved = $true
        $Card.Effect = $null
        $Pill.Effect = $null
      }
    }
    if ($script:hasMoved) {
      $window.Left = $window.Left + ($p.X - $script:lastPos.X)
      $window.Top  = $window.Top  + ($p.Y - $script:lastPos.Y)
      $script:lastPos = $p
    }
  })
  $window.Add_MouseLeftButtonUp({
    if (-not $script:mouseDown) { return }
    $script:mouseDown = $false
    $null = $window.ReleaseMouseCapture()
    if ($script:hasMoved) {
      $Card.Effect = $script:shadowEffect
      $Pill.Effect = $script:pillShadow
      $cx = $window.Left + $window.Width / 2
      $cy = $window.Top + $window.Height / 2
      $edge = Find-Edge $cx $cy
      if ($edge) { Collapse-Pill $edge } else { $script:docked = $false }
      Save-Position
    } else {
      Start-Process $script:siteCfg.openUrl
    }
  })
  # 鼠标碰到角标 → 弹出；离开卡片 → 自动收回
  $window.Add_MouseEnter({
    if ($Pill.Visibility -eq 'Visible') {
      $script:collapseTimer.Stop()
      Expand-Card $true $script:dockEdge 0 0
    }
  })
  $window.Add_MouseLeave({
    if ($script:docked -and $Card.Visibility -eq 'Visible' -and -not $script:mouseDown) {
      $script:collapseTimer.Start()
    }
  })

  # ---------- 右键菜单 ----------
  function New-WidgetMenu {
    $m = New-Object System.Windows.Controls.ContextMenu
    $miRefresh = New-Object System.Windows.Controls.MenuItem
    $miRefresh.Header = '刷新余额'
    $miRefresh.Add_Click({ Update-Balance })
    $null = $m.Items.Add($miRefresh)

    $miOpen = New-Object System.Windows.Controls.MenuItem
    $miOpen.Header = '打开网页（充值）'
    $miOpen.Add_Click({ Start-Process $script:siteCfg.openUrl })
    $null = $m.Items.Add($miOpen)

    $miCopy = New-Object System.Windows.Controls.MenuItem
    $miCopy.Header = '复制余额'
    $miCopy.Add_Click({ if ($BalanceText.Text) { Set-Clipboard -Value $BalanceText.Text } })
    $null = $m.Items.Add($miCopy)

    $miAuto = New-Object System.Windows.Controls.MenuItem
    $miAuto.Header = '开机自启'
    $miAuto.IsCheckable = $true
    $miAuto.IsChecked = Test-AutoStart
    # 注意：事件处理器里不能引用本函数的局部变量（函数返回后即失效），一律用 $this
    $miAuto.Add_Click({ Set-AutoStart ([bool]$this.IsChecked) })
    $null = $m.Items.Add($miAuto)

    $miDock = New-Object System.Windows.Controls.MenuItem
    $miDock.Tag = 'dock-toggle'
    $miDock.Add_Click({
      if ($Pill.Visibility -eq 'Visible') {
        $cx = $window.Left + $window.Width / 2
        $cy = $window.Top + $window.Height / 2
        Expand-Card $false $null $cx $cy
      } else {
        $edge = Find-Edge ($window.Left + $window.Width / 2) ($window.Top + $window.Height / 2) $true
        Collapse-Pill $edge
      }
      Save-Position
    })
    $m.Add_Opened({
      $item = $this.Items | Where-Object { $_.Tag -eq 'dock-toggle' } | Select-Object -First 1
      if ($item) {
        if ($Pill.Visibility -eq 'Visible') { $item.Header = '展开角标' }
        else { $item.Header = '收起成角标（贴边）' }
      }
    })
    $null = $m.Items.Add($miDock)

    $miEdit = New-Object System.Windows.Controls.MenuItem
    $miEdit.Header = '编辑配置'
    $miEdit.Add_Click({ Start-Process notepad.exe -ArgumentList "`"$script:configPath`"" })
    $null = $m.Items.Add($miEdit)

    $miWizard = New-Object System.Windows.Controls.MenuItem
    $miWizard.Header = '配置向导…'
    $miWizard.Add_Click({
      $wiz = Join-Path $script:scriptDir '配置向导.vbs'
      if (Test-Path $wiz) { Start-Process "$env:WINDIR\System32\wscript.exe" -ArgumentList "`"$wiz`"" }
    })
    $null = $m.Items.Add($miWizard)

    $miQuit = New-Object System.Windows.Controls.MenuItem
    $miQuit.Header = '退出'
    $miQuit.Add_Click({ $window.Close() })
    $null = $m.Items.Add($miQuit)

    return $m
  }
  $menu = New-WidgetMenu
  $menuPill = New-WidgetMenu
  $Card.ContextMenu = $menu
  $Pill.ContextMenu = $menuPill

  # ---------- 定时刷新 ----------
  $timer = New-Object System.Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromSeconds([double]$sc.refreshSeconds)
  $timer.Add_Tick({ Update-Balance })
  $timer.Start()

  # ---------- 轮询异步请求结果（1 秒一次） ----------
  $pollTimer = New-Object System.Windows.Threading.DispatcherTimer
  $pollTimer.Interval = [TimeSpan]::FromSeconds(1)
  $pollTimer.Add_Tick({
    if (-not $script:fetchHandle) { return }
    if (-not $script:fetchHandle.IsCompleted) {
      if ($script:fetchStarted -and ((Get-Date) - $script:fetchStarted).TotalSeconds -gt 40) {
        try { $script:fetchPs.Stop() } catch { }
      }
      return
    }
    $result = $null
    try {
      $result = $script:fetchPs.EndInvoke($script:fetchHandle) | Select-Object -First 1
    } catch {
      Show-Status "请求失败：$($_.Exception.Message)" 'err'
      Set-Dot '#F0716F'
    } finally {
      try { $script:fetchPs.Dispose() } catch { }
      $script:fetchPs = $null
      $script:fetchHandle = $null
      $script:fetchStarted = $null
    }
    if ($result) {
      if ($result.Ok) { Handle-Response 200 $result.Json '' }
      else { Handle-Response $result.Code '' $result.Err }
    }
  })
  $pollTimer.Start()

  # ---------- 冒烟测试：短暂显示后自动关闭 ----------
  if ($SmokeTest) {
    $st = New-Object System.Windows.Threading.DispatcherTimer
    $st.Interval = [TimeSpan]::FromSeconds(5)
    $st.Add_Tick({ $window.Close() })
    $st.Start()
    # 顺带验证贴边收起/展开逻辑（不写配置）
    try {
      Collapse-Pill 'right'
      Expand-Card $true 'right' 0 0
      Collapse-Pill 'bottom'
    } catch { }
    # 验证右键菜单的 Opened 处理器（Tag/$this 模式）不报错
    try {
      $menu.IsOpen = $true
      $menu.IsOpen = $false
      $menuPill.IsOpen = $true
      $menuPill.IsOpen = $false
    } catch { throw }
  }

  Update-Balance

  # 确保静默启动器存在（vbs）
  Ensure-Launchers

  $window.Add_Closed({
    if (-not $SmokeTest) { Save-Position }
    try { if ($script:fetchHandle -and -not $script:fetchHandle.IsCompleted) { $script:fetchPs.Stop() } } catch { }
    try { if ($script:fetchPs) { $script:fetchPs.Dispose() } } catch { }
    if ($SmokeTest) {
      try { Set-Content -Path (Join-Path $script:scriptDir '_smoke-result.txt') -Value "BALANCE: $($BalanceText.Text)`nSTATUS: $($StatusText.Text)`nDOCK: $($script:docked)/$($script:dockEdge)" -Encoding UTF8 } catch { }
    }
  })

  $app = New-Object System.Windows.Application
  $app.Run($window) | Out-Null
}

try {
  Main
  if ($SmokeTest) { Write-Output 'SMOKE-OK' }
} catch {
  $msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($_.Exception.ToString())`n$($_.ScriptStackTrace)"
  try { Add-Content -Path $script:errorLog -Value $msg -Encoding UTF8 } catch { }
  if ($SmokeTest) { Write-Output "SMOKE-FAIL: $($_.Exception.Message)" }
  exit 1
}
