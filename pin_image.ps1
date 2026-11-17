<#
  pin_image.ps1 - shows an image on top of every window on Windows.

    pin_image.ps1 photo.jpg
    pin_image.ps1 photo.jpg -Width 400
    pin_image.ps1 photo.jpg -Crop width -Width 600 -NoTaskbar

  Drag it anywhere. Wheel resizes around the cursor. Right click for options.
  Keys: T topmost, C click-through (Ctrl+Alt+L to undo), O opacity, R reset size,
  [ ] resize, Esc quit.

  The last image, size and spot are remembered in %LOCALAPPDATA%\pinimage.json.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string] $Image,
  [ValidateRange(24, 4096)][double] $Width = 320,
  [ValidateRange(24, 4096)][double] $Height = 320,
  [ValidateSet('square','fit','stretch','width','height')][string] $Crop = 'square',
  [ValidateRange(-1, 100000)][int] $X = -1,
  [ValidateRange(-1, 100000)][int] $Y = -1,
  [ValidateRange(0, 400)][double] $Radius = 0,
  [switch] $ClickThrough,
  [switch] $NoTopmost,
  [switch] $NoTaskbar,
  [switch] $Forget
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

Add-Type -Language CSharp -Namespace Pin -Name Win32 -MemberDefinition @'
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }

  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
  [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);

  public const int GWL_EXSTYLE = -20;
  public const int WS_EX_LAYERED = 0x80000, WS_EX_TRANSPARENT = 0x20;
  public const int WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000, WS_EX_TOPMOST = 0x8;
'@

# PowerShell hosts are DPI unaware by default, and mixing their physical screen bounds
# with WPF's DIP coordinates makes the window creep off screen every launch.
try {
  if (-not [Pin.Win32]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
    [void] [Pin.Win32]::SetProcessDPIAware()
  }
} catch { }

$work = [System.Windows.SystemParameters]::WorkArea

function Load-Image([string] $path) {
  if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
  try {
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $stream = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $path).ProviderPath)
    $bmp.BeginInit()
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.StreamSource = $stream
    $bmp.EndInit()
    $bmp.Freeze()
    $stream.Dispose()
    return $bmp
  } catch {
    Write-Warning "cannot read '$path': $($_.Exception.Message)"
    return $null
  }
}

# no argument: whatever was pinned last time, else the newest picture in this folder
$stateFile = Join-Path $env:LOCALAPPDATA 'pinimage.json'
$state = $null
if (-not $Forget.IsPresent -and (Test-Path -LiteralPath $stateFile)) {
  try { $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { }
}
if (-not $Image -and $state -and $state.image -and (Test-Path -LiteralPath $state.image)) {
  $Image = $state.image
}
if (-not $Image) {
  $Image = Get-ChildItem -LiteralPath (Split-Path -Parent $PSCommandPath) -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '^\.(png|jpe?g|bmp|gif|webp)$' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Image) {
  Write-Error 'no image given and none found.  usage: pin_image.ps1 <file> [-Width 400]'
}

$img = Load-Image $Image
if (-not $img) { Write-Error "cannot open '$Image'" }
$path = (Resolve-Path -LiteralPath $Image).ProviderPath

$aspect = if ($img.Height -gt 0) { $img.Width / $img.Height } else { 1 }

$win = New-Object System.Windows.Window
$win.WindowStyle = 'None'
# a layered window is what keeps Aero Snap away: the shell declines these, and with no
# caption there is nothing for it to grab on a drag either
$win.AllowsTransparency = $true
$win.ResizeMode = 'NoResize'
$win.ShowInTaskbar = -not $NoTaskbar.IsPresent
$win.Topmost = -not $NoTopmost.IsPresent
$win.Title = 'pinned image'
$win.MinWidth = 24; $win.MinHeight = 24
$win.WindowStartupLocation = 'Manual'
$win.AllowDrop = $true
$win.Background = [System.Windows.Media.Brushes]::Transparent
$win.UseLayoutRounding = $true

$pic = New-Object System.Windows.Controls.Image
[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($pic, 'HighQuality')
$pic.Source = $img
$pic.Stretch = switch ($Crop) {
  'square' { 'UniformToFill' }
  'stretch' { 'Fill' }
  default { 'Uniform' }
}
$win.Content = $pic

function Round-Corners {
  # the clip has to follow the drawn rect, not the window rect, or fit mode gets
  # rounded corners on the empty margins instead of on the picture
  if ($Radius -le 0) { $pic.Clip = $null; return }
  $w = $pic.ActualWidth; $h = $pic.ActualHeight
  if ($w -le 1 -or $h -le 1) { return }
  $iw = $w; $ih = $h
  if ($Crop -in 'fit', 'width', 'height') {
    $k = [Math]::Min($w / $pic.Source.Width, $h / $pic.Source.Height)
    $iw = $pic.Source.Width * $k; $ih = $pic.Source.Height * $k
  }
  $g = New-Object System.Windows.Media.RectangleGeometry(($w - $iw) / 2, ($h - $ih) / 2, $iw, $ih, $Radius, $Radius)
  $g.Freeze()
  $pic.Clip = $g
}

# what size the window should be for the current crop mode
function Fit-Size([double] $w, [double] $h) {
  if ($Crop -eq 'square') { return @{ w = $w; h = $w } }
  if ($Crop -eq 'stretch') { return @{ w = $w; h = $h } }
  if ($Crop -eq 'height') { return @{ w = $h * $aspect; h = $h } }
  return @{ w = $w; h = $w / $aspect }
}

function Keep-Inside {
  $maxL = [Math]::Max($work.Left, $work.Right - $win.Width)
  $maxT = [Math]::Max($work.Top, $work.Bottom - $win.Height)
  $l = [Math]::Max($work.Left, [Math]::Min($maxL, $win.Left))
  $t = [Math]::Max($work.Top, [Math]::Min($maxT, $win.Top))
  if ([Math]::Abs($l - $win.Left) -gt 0.5) { $win.Left = $l }
  if ([Math]::Abs($t - $win.Top) -gt 0.5) { $win.Top = $t }
}

$script:wantW = 0.0; $script:wantH = 0.0
$script:applying = $false

function Set-Size([double] $w, [double] $h, [switch] $AtCursor) {
  $f = Fit-Size $w $h
  $w = [Math]::Max(24, [Math]::Min(4096, [double] $f.w))
  $h = [Math]::Max(24, [Math]::Min(4096, [double] $f.h))
  $script:wantW = $w; $script:wantH = $h
  $script:applying = $true
  try {
    if ($AtCursor) {
      # grow away from the cursor so the detail you are looking at stays in place
      $pt = New-Object Pin.Win32+POINT
      [void] [Pin.Win32]::GetCursorPos([ref] $pt)
      $src = [System.Windows.Interop.HwndSource]::FromVisual($win)
      if ($src) {
        $m = $src.CompositionTarget.TransformFromDevice
        $c = $m.Transform((New-Object System.Windows.Point([double] $pt.X, [double] $pt.Y)))
      } else {
        $c = New-Object System.Windows.Point([double] $pt.X, [double] $pt.Y)
      }
      $rx = ($c.X - $win.Left) / [Math]::Max(1, $win.Width)
      $ry = ($c.Y - $win.Top) / [Math]::Max(1, $win.Height)
      $win.Width = $w; $win.Height = $h
      $win.Left = $c.X - $rx * $w
      $win.Top = $c.Y - $ry * $h
    } else {
      $px = $win.Left + $win.Width / 2; $py = $win.Top + $win.Height / 2
      $win.Width = $w; $win.Height = $h
      $win.Left = $px - $w / 2; $win.Top = $py - $h / 2
    }
    Keep-Inside
    Round-Corners
  } finally { $script:applying = $false }
}

function Save-State {
  if ($Forget.IsPresent) { return }
  try {
    [pscustomobject]@{
      image = $script:path
      w = [int] $script:wantW; h = [int] $script:wantH
      x = [int] $win.Left; y = [int] $win.Top
      crop = $Crop; radius = $Radius
      topmost = $win.Topmost; opacity = $win.Opacity
      recent = @($script:recent)
    } | ConvertTo-Json -Depth 3 -Compress | Set-Content -LiteralPath $stateFile -Encoding UTF8
  } catch { }
}

# history of faces so a previous image is one click away
$script:recent = @()
if ($state -and $state.recent) {
  $script:recent = @($state.recent | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
}
function Add-Recent([string] $p) {
  if (-not $p) { return }
  $script:recent = @(@($p) + $script:recent | Where-Object { $_ } | Select-Object -Unique -First 8)
}
Add-Recent $script:path

$wantW = $Width; $wantH = $Height
if ($state -and -not $PSBoundParameters.ContainsKey('Width') -and $state.w -gt 20) { $wantW = [double] $state.w }
if ($state -and -not $PSBoundParameters.ContainsKey('Height') -and $state.h -gt 20) { $wantH = [double] $state.h }
if (-not $PSBoundParameters.ContainsKey('Crop') -and $state -and
    $state.crop -in 'square', 'fit', 'stretch', 'width', 'height') {
  $Crop = $state.crop
  $pic.Stretch = switch ($Crop) { 'square' { 'UniformToFill' } 'stretch' { 'Fill' } default { 'Uniform' } }
}
if (-not $PSBoundParameters.ContainsKey('Radius') -and $state -and $state.radius -ge 0) { $Radius = [double] $state.radius }
if ($state -and $state.psobject.Properties.Name -contains 'topmost') { $win.Topmost = [bool] $state.topmost }
if ($state -and $state.opacity -gt 0.2) { $win.Opacity = [double] $state.opacity }
if ($X -lt 0 -and $Y -lt 0 -and $state) { $X = [int] $state.x; $Y = [int] $state.y }

$f = Fit-Size $wantW $wantH
$script:wantW = [double] $f.w; $script:wantH = [double] $f.h
if ($X -lt 0) { $X = $work.Right - $script:wantW - 40 }
if ($Y -lt 0) { $Y = $work.Top + 60 }
$win.Width = $script:wantW; $win.Height = $script:wantH
$win.Left = $X; $win.Top = $Y
Keep-Inside

$script:clickThrough = $ClickThrough.IsPresent
$helper = New-Object System.Windows.Interop.WindowInteropHelper($win)
$HOTKEY = 0xB0BA

function Apply-Styles {
  $h = $helper.Handle
  if ($h -eq [IntPtr]::Zero) { return }
  $mask = [Pin.Win32]::WS_EX_LAYERED -bor [Pin.Win32]::WS_EX_TRANSPARENT -bor
          [Pin.Win32]::WS_EX_TOOLWINDOW -bor [Pin.Win32]::WS_EX_APPWINDOW
  $ex = [Pin.Win32]::GetWindowLong($h, [Pin.Win32]::GWL_EXSTYLE) -band (-bnot $mask)
  if ($NoTaskbar.IsPresent) { $ex = $ex -bor [Pin.Win32]::WS_EX_TOOLWINDOW }
  if ($script:clickThrough) { $ex = $ex -bor ([Pin.Win32]::WS_EX_LAYERED -bor [Pin.Win32]::WS_EX_TRANSPARENT) }
  [void] [Pin.Win32]::SetWindowLong($h, [Pin.Win32]::GWL_EXSTYLE, $ex)
}

$hook = [System.Windows.Interop.HwndSourceHook] {
  param([IntPtr] $h, [int] $msg, [IntPtr] $wParam, [IntPtr] $lParam, [ref] $handled)
  switch ($msg) {
    # Win+Up or Win+arrows ask for maximize/minimize. Answering would turn a pinned
    # picture into a full screen window, so refuse and stay put.
    0x0112 {
      $cmd = ([long] $wParam) -band 0xFFF0
      if ($cmd -eq 0xF020 -or $cmd -eq 0xF030) { $handled.Value = $true; return [IntPtr]::Zero }
    }
    # Ctrl+Alt+L: the only way back once the picture ignores the mouse
    0x0312 {
      if (([long] $wParam) -eq $HOTKEY) {
        $handled.Value = $true
        Toggle-ClickThrough
        return [IntPtr]::Zero
      }
    }
  }
  $handled.Value = $false
  return [IntPtr]::Zero
}

# the window tracks the size it asked for; anything else was the shell's doing
$win.Add_SizeChanged({
  if ($script:applying) { return }
  if ([Math]::Abs($win.Width - $script:wantW) -gt 1.5 -or [Math]::Abs($win.Height - $script:wantH) -gt 1.5) {
    $win.Dispatcher.BeginInvoke([System.Action] { Set-Size $script:wantW $script:wantH })
  }
})
$win.Add_StateChanged({
  if ($win.WindowState -ne 'Normal') {
    $win.WindowState = 'Normal'
    Set-Size $script:wantW $script:wantH
  }
})
$win.Add_LocationChanged({ if (-not $script:applying -and -not $script:dragging) { Keep-Inside } })
$pic.Add_SizeChanged({ Round-Corners })

# DragMove is the usual way to do this, but it silently does nothing on a layered
# window in some WPF builds, so the move is done by hand with mouse capture
$script:dragging = $false
$script:grabX = 0.0; $script:grabY = 0.0

function Cursor-OnScreen {
  $pt = New-Object Pin.Win32+POINT
  [void] [Pin.Win32]::GetCursorPos([ref] $pt)
  $src = [System.Windows.Interop.HwndSource]::FromVisual($win)
  if ($src) {
    return $src.CompositionTarget.TransformFromDevice.Transform(
      (New-Object System.Windows.Point([double] $pt.X, [double] $pt.Y)))
  }
  return New-Object System.Windows.Point([double] $pt.X, [double] $pt.Y)
}

$win.Add_MouseLeftButtonDown({
  if ($script:clickThrough) { return }
  $c = Cursor-OnScreen
  $script:grabX = $c.X - $win.Left
  $script:grabY = $c.Y - $win.Top
  $script:dragging = $true
  [void] $win.CaptureMouse()
  $_.Handled = $true
})
$win.Add_PreviewMouseMove({
  if (-not $script:dragging) { return }
  $c = Cursor-OnScreen
  $win.Left = $c.X - $script:grabX
  $win.Top = $c.Y - $script:grabY
})
$win.Add_PreviewMouseLeftButtonUp({
  if (-not $script:dragging) { return }
  $script:dragging = $false
  [void] $win.ReleaseMouseCapture()
  Keep-Inside; Save-State
})
$win.Add_LostMouseCapture({
  if ($script:dragging) { $script:dragging = $false; Keep-Inside; Save-State }
})

$win.Add_PreviewMouseWheel({
  $k = if ($_.Delta -gt 0) { 1.06 } else { 1 / 1.06 }
  Set-Size ($script:wantW * $k) ($script:wantH * $k) -AtCursor
  $_.Handled = $true
  Save-State
})

function Set-Image([string] $p) {
  $loaded = Load-Image $p
  if (-not $loaded) { return }
  $script:img = $loaded
  $pic.Source = $loaded
  $script:path = (Resolve-Path -LiteralPath $p).ProviderPath
  $script:aspect = if ($loaded.Height -gt 0) { $loaded.Width / $loaded.Height } else { 1 }
  Add-Recent $script:path
  if ($Crop -notin 'square', 'stretch') { Set-Size $script:wantW $script:wantW }
  Round-Corners
  Write-Host "pinned $script:path"
}

$win.Add_Drop({
  if (-not $_.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { return }
  $files = [string[]] $_.Data.GetData([System.Windows.DataFormats]::FileDrop)
  $first = $files | Where-Object { $_ -match '\.(png|jpe?g|gif|bmp|ico|webp|tiff?)$' } | Select-Object -First 1
  if ($first) { Set-Image $first; Save-State }
  $_.Handled = $true
})
$win.Add_DragOver({
  $_.Effects = if ($_.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { 'Copy' } else { 'None' }
  $_.Handled = $true
})

# a plain topmost window still loses its layer now and then when another app pushes
# itself forward, so nudge the layer back without touching anything else
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(350)
$timer.Add_Tick({
  if (-not $win.Topmost -or $script:dragging) { return }
  $h = $helper.Handle
  if ($h -eq [IntPtr]::Zero) { return }
  $fg = [Pin.Win32]::GetForegroundWindow()
  if ($fg -eq $h) { return }
  if (([Pin.Win32]::GetWindowLong($fg, [Pin.Win32]::GWL_EXSTYLE) -band [Pin.Win32]::WS_EX_TOPMOST) -eq 0) {
    $win.Topmost = $false
    $win.Topmost = $true
  }
})

$opacities = @(1.0, 0.85, 0.65, 0.45, 0.28)
$script:oi = 0

function Toggle-Topmost {
  $win.Topmost = -not $win.Topmost
  Save-State
}
function Toggle-ClickThrough {
  $script:clickThrough = -not $script:clickThrough
  Apply-Styles
  if ($script:miClick) {
    $script:miClick.Header = if ($script:clickThrough) { 'stop ignoring the mouse  (Ctrl+Alt+L)' } else { 'ignore the mouse' }
  }
}
function Cycle-Opacity {
  $script:oi = ($script:oi + 1) % $opacities.Length
  $win.Opacity = $opacities[$script:oi]
  Save-State
}
function Zoom([double] $k) { Set-Size ($script:wantW * $k) ($script:wantH * $k) }

$menu = New-Object System.Windows.Controls.ContextMenu
function Add-Item([string] $text, [scriptblock] $action) {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = $text
  [void] $menu.Items.Add($mi)
  if ($action) { $mi.Add_Click($action) }
  return $mi
}

$script:miClick = Add-Item $(if ($ClickThrough.IsPresent) { 'stop ignoring the mouse  (Ctrl+Alt+L)' } else { 'ignore the mouse' }) { Toggle-ClickThrough }
Add-Item 'stay on top  (T)' { Toggle-Topmost } | Out-Null
Add-Item 'fade  (O)' { Cycle-Opacity } | Out-Null
Add-Item 'reset size  (R)' { Set-Size 320 320; Save-State } | Out-Null
Add-Item 'choose another image...' {
  $dlg = New-Object Microsoft.Win32.OpenFileDialog
  $dlg.Filter = 'Images|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp|All files|*.*'
  $dlg.InitialDirectory = Split-Path -Parent $script:path
  if ($dlg.ShowDialog($win)) { Set-Image $dlg.FileName; Save-State }
} | Out-Null

$crops = New-Object System.Windows.Controls.MenuItem
$crops.Header = 'crop'
foreach ($c in 'square', 'fit', 'stretch', 'width', 'height') {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = $c
  $mi.Add_Click({
    param($s, $e)
    $script:Crop = $s.Header.ToString()
    $pic.Stretch = switch ($script:Crop) { 'square' { 'UniformToFill' } 'stretch' { 'Fill' } default { 'Uniform' } }
    Set-Size $script:wantW $script:wantH
    Save-State
  })
  [void] $crops.Items.Add($mi)
}
[void] $menu.Items.Add($crops)

$sizes = New-Object System.Windows.Controls.MenuItem
$sizes.Header = 'size'
foreach ($s in 120, 200, 320, 480, 640, 900) {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = "$s px"
  $px = $s
  $mi.Add_Click({ Set-Size $px $px; Save-State }.GetNewClosure())
  [void] $sizes.Items.Add($mi)
}
[void] $menu.Items.Add($sizes)

$recent = New-Object System.Windows.Controls.MenuItem
$recent.Header = 'recent'
$recent.Add_SubmenuOpened({
  $recent.Items.Clear()
  if ($script:recent.Count -eq 0) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = '(nothing yet)'
    $mi.IsEnabled = $false
    [void] $recent.Items.Add($mi)
    return
  }
  foreach ($p in $script:recent) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = Split-Path $p -Leaf
    $mi.ToolTip = $p
    $mi.Add_Click({ Set-Image $p; Save-State }.GetNewClosure())
    [void] $recent.Items.Add($mi)
  }
})
[void] $menu.Items.Add($recent)

[void] $menu.Items.Add((New-Object System.Windows.Controls.Separator))
Add-Item 'unpin  (Esc)' { $win.Close() } | Out-Null
$win.ContextMenu = $menu

$win.Add_PreviewKeyDown({
  switch ($_.Key.ToString()) {
    'Escape' { $_.Handled = $true; $win.Close() }
    'T' { $_.Handled = $true; Toggle-Topmost }
    'C' { $_.Handled = $true; Toggle-ClickThrough }
    'O' { $_.Handled = $true; Cycle-Opacity }
    'R' { $_.Handled = $true; Set-Size 320 320; Save-State }
    'OemOpenBrackets' { $_.Handled = $true; Zoom (1 / 1.08) }
    'OemCloseBrackets' { $_.Handled = $true; Zoom 1.08 }
  }
})

$win.Add_ContentRendered({
  $src = [System.Windows.Interop.HwndSource]::FromVisual($win)
  if ($src) { $src.AddHook($hook) }
  Apply-Styles
  if (-not [Pin.Win32]::RegisterHotKey($helper.Handle, $HOTKEY, 0x0003, 0x4C)) {
    Write-Warning 'Ctrl+Alt+L is taken, so click-through can only be undone by unpinning'
  }
  Round-Corners
  $win.Activate()
  $timer.Start()
})

$win.Add_Closed({
  if ($helper.Handle -ne [IntPtr]::Zero) {
    [void] [Pin.Win32]::UnregisterHotKey($helper.Handle, $HOTKEY)
  }
  $timer.Stop()
  Save-State
})

Write-Host "pinned $path  ($([int] $script:wantW)x$([int] $script:wantH), $Crop crop)"
Write-Host 'drag to move, wheel to resize, right click for options, Esc to unpin'
[void] $win.ShowDialog()
