<#
  make_shortcut.ps1 - puts a "Pin Image" entry on the Desktop so you can double click
  an image at it instead of typing command lines.

    powershell -File make_shortcut.ps1
    powershell -File make_shortcut.ps1 -AtStartup   # also start it when you log in
#>
param([switch] $AtStartup)

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $PSCommandPath
$ps = Join-Path $dir 'pin_image.ps1'
if (-not (Test-Path $ps)) { throw "pin_image.ps1 not next to me, in $dir" }

# wscript runs the script with no console window flashing up
$inner = Join-Path $dir 'pin_image.vbs'
@"
Set sh = CreateObject("WScript.Shell")
sh.Run """powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""$ps"" ""%1""", 0, False
"@ | Set-Content -LiteralPath $inner -Encoding ASCII

$sh = New-Object -ComObject WScript.Shell
$places = @([Environment]::GetFolderPath('Desktop'))
if ($AtStartup) { $places += $sh.SpecialFolders('Startup') }

foreach ($p in $places) {
  $lnk = Join-Path $p 'Pin Image.lnk'
  $s = $sh.CreateShortcut($lnk)
  $s.TargetPath = "$env:WINDIR\System32\wscript.exe"
  $s.Arguments = "`"$inner`""
  $s.WorkingDirectory = $dir
  $s.Description = 'pin an image on top of every window'
  $ico = Join-Path $dir 'pin.ico'
  if (Test-Path $ico) { $s.IconLocation = $ico }
  $s.Save()
  "wrote $lnk"
}

'Drag an image file onto the shortcut to pin it. Run the script directly to get the last one back.'
