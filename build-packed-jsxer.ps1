# build-packed-jsxer.ps1 — Single-file EXE builder that EMBEDS your release folder and sets a custom icon.
# At runtime the EXE:
#   - Prompts for input (original never modified)
#   - Creates "<selectedfilename>-JsxerLogs\temp"
#   - Copies original into temp (works only on the copy/blob)
#   - Decodes with embedded jsxer.exe
#   - Writes "<selectedfilename>-jsxer.jsx" next to original
#   - Copies renamed temp copy "<selectedfilename>-Jsxer<ext>" next to original
#   - Logs to "<selectedfilename>-JsxerLogs"
#   - Rewrites decoded header to your custom block
# Build output is timestamped and uses icon_jsxer.ico if present.

$ErrorActionPreference = 'Stop'

# --- Locate project root ---
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = (Get-Location).Path }
Set-Location $Root

# --- Required files to embed ---
$RelExe = Join-Path $Root 'release\jsxer.exe'
$RelDll = Join-Path $Root 'release\dll\lib-jsxer.dll'
$RelLib = Join-Path $Root 'release\static\libjsxer.lib'

foreach ($p in @($RelExe,$RelDll,$RelLib)) {
  if (-not (Test-Path $p)) { Write-Host "ERROR: Missing: $p" -ForegroundColor Red; exit 1 }
}

function Get-B64([string]$path) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) }

Write-Host "Embedding binaries..."
$b64_jsxer = Get-B64 $RelExe
$b64_dll   = Get-B64 $RelDll
$b64_lib   = Get-B64 $RelLib

# ---------------- RUNTIME WRAPPER (compiled into the EXE) ----------------
$Wrapper = @'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

function NowISO { (Get-Date).ToUniversalTime().ToString("s") + "Z" }

function Write-Blob([string]$b64, [string]$destFullPath) {
  $dir = Split-Path -Parent $destFullPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [IO.File]::WriteAllBytes($destFullPath, [Convert]::FromBase64String($b64))
}

function Get-MD5($path) {
  if (-not (Test-Path $path)) { return "" }
  $md5=[System.Security.Cryptography.MD5]::Create()
  $fs=[System.IO.File]::OpenRead($path)
  try { (-join ($md5.ComputeHash($fs) | ForEach-Object { $_.ToString("x2") })) }
  finally { $fs.Dispose(); $md5.Dispose() }
}

function Ensure-Blob($inPath, [ref]$usedInput, [ref]$cleanupTmp) {
  $cleanupTmp.Value = $false
  try { $txt = Get-Content -Raw -Path $inPath -ErrorAction Stop } catch {
    $usedInput.Value = $inPath; return
  }
  if ($txt.TrimStart().StartsWith('@JSXBIN@')) { $usedInput.Value = $inPath; return }
  $m = [regex]::Match($txt, '@JSXBIN@.*', 'Singleline')
  if ($m.Success) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("jsxer_blob_{0}.jsxbin" -f ([guid]::NewGuid()))
    [IO.File]::WriteAllText($tmp,$m.Value,[Text.Encoding]::ASCII)
    $usedInput.Value = $tmp; $cleanupTmp.Value = $true
  } else { throw "Selected file does not contain an @JSXBIN@ blob." }
}

# === Embedded payloads (set by builder) ===
$B64_JSXER = "__B64_JSXER__"
$B64_DLL   = "__B64_DLL__"
$B64_LIB   = "__B64_LIB__"

# === Extract payloads to a private runtime dir ===
$Base = Join-Path $env:LOCALAPPDATA 'JSXER-Decoder\1.7.4'
$Rel  = Join-Path $Base 'release'
$JSXER_EXE = Join-Path $Rel 'jsxer.exe'
$DLL_PATH  = Join-Path $Rel 'dll\lib-jsxer.dll'
$LIB_PATH  = Join-Path $Rel 'static\libjsxer.lib'

Write-Blob $B64_JSXER $JSXER_EXE
Write-Blob $B64_DLL   $DLL_PATH
Write-Blob $B64_LIB   $LIB_PATH

# === Pick INPUT ===
$ofd = New-Object Windows.Forms.OpenFileDialog
$ofd.InitialDirectory = [Environment]::GetFolderPath('Desktop')
$ofd.Filter = 'JSXBIN/JS files (*.jsxbin;*.js;*.jsx)|*.jsxbin;*.js;*.jsx|All files (*.*)|*.*'
$ofd.Title  = 'Select .jsxbin or wrapped .jsx/.js to decode'
$ofd.Multiselect = $false
if ($ofd.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 0 }
$Selected = $ofd.FileName
if ([string]::IsNullOrWhiteSpace($Selected)) { exit 0 }

# === Prepare paths ===
$DirIn  = Split-Path -Parent $Selected
$NameIn = [IO.Path]::GetFileNameWithoutExtension($Selected)
$ExtIn  = [IO.Path]::GetExtension($Selected)

# Logs root: "<selectedfilename>-JsxerLogs" next to original
$LogsRoot = Join-Path $DirIn ("{0}-JsxerLogs" -f $NameIn)
$TempDir  = Join-Path $LogsRoot 'temp'
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null

# Copy the original into temp FIRST (we only work on copies)
$TempCopy = Join-Path $TempDir ([IO.Path]::GetFileName($Selected))
Copy-Item $Selected $TempCopy -Force

# After decode, DROP a renamed copy of this temp file at the original location:
$RenamedCopyAtDest = Join-Path $DirIn ("{0}-Jsxer{1}" -f $NameIn, $ExtIn)

# Decoded output (always next to ORIGINAL file)
$DecodedOut = Join-Path $DirIn ("{0}-jsxer.jsx" -f $NameIn)

# Logs/err inside LogsRoot
$ErrPath = Join-Path $LogsRoot 'stderr.txt'
$LogPath = Join-Path $LogsRoot 'decode.log'

# Desired header block
$DesiredHeader = "/*`n* Decompiled with Jsxer https://github.com/AngeloD2022/jsxer/tree/v1.7.4`n* Jsxer-Decoder by Vibe`n* Version: 1.7.4`n* JSXBIN 2.0`n*/`r`n"

$Start = (Get-Date).ToUniversalTime().ToString("s") + "Z"

$UsedInput=$null; $Cleanup=$false
$ExitCode = -1
$Stdout   = ""
$Stderr   = ""

try {
  Ensure-Blob $TempCopy ([ref]$UsedInput) ([ref]$Cleanup)

  # Run jsxer on the USED INPUT (TempCopy or extracted blob)
  $psi = [Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $JSXER_EXE
  $psi.Arguments = '"' + $UsedInput + '"'
  $psi.WorkingDirectory = $Rel
  $psi.UseShellExecute=$false
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true

  $p = [Diagnostics.Process]::new(); $p.StartInfo=$psi
  $null=$p.Start()
  $Stdout=$p.StandardOutput.ReadToEnd()
  $Stderr=$p.StandardError.ReadToEnd()
  $p.WaitForExit(); $ExitCode=$p.ExitCode

  # Replace or prepend header in decoded text
  $DecodedText = $Stdout
  $regex = New-Object System.Text.RegularExpressions.Regex('^\s*/\*.*?\*/\s*', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($regex.IsMatch($DecodedText)) {
    $DecodedText = $regex.Replace($DecodedText, $DesiredHeader, 1)
  } else {
    $DecodedText = $DesiredHeader + $DecodedText
  }

  [IO.File]::WriteAllText($DecodedOut, $DecodedText, [Text.Encoding]::UTF8)
  [IO.File]::WriteAllText($ErrPath,$Stderr,[Text.Encoding]::UTF8)

  # Rename the TEMP COPY and copy it to original location
  $TempRenamed = Join-Path $TempDir ("{0}-Jsxer{1}" -f $NameIn,$ExtIn)
  Move-Item -Path $TempCopy -Destination $TempRenamed -Force
  Copy-Item -Path $TempRenamed -Destination $RenamedCopyAtDest -Force
}
catch {
  $Stderr += "`nFATAL: $($_.Exception.Message)"
}
finally {
  if ($Cleanup -and $UsedInput -and (Test-Path $UsedInput)) { Remove-Item $UsedInput -ErrorAction SilentlyContinue }
}

$End = (Get-Date).ToUniversalTime().ToString("s") + "Z"

# Build LOG
$Lines=@()
$Lines += "JSXER Decoder log"
$Lines += "start: $Start"
$Lines += "end:   $End"
$Lines += ""
$Lines += "runtime_base:  $Base"
$Lines += "jsxer_path:    $JSXER_EXE"
$Lines += "dll_path:      $DLL_PATH"
$Lines += "lib_path:      $LIB_PATH"
$Lines += ""
$Lines += "original_file: $Selected"
$Lines += "temp_copy:     $TempCopy"
$Lines += "used_input:    $UsedInput"
if (Test-Path $UsedInput) { $Lines += "used_input_size: " + (Get-Item $UsedInput).Length; $Lines += "used_input_md5: " + (Get-MD5 $UsedInput) }
$Lines += "exit_code:     $ExitCode"
$Lines += ""
$Lines += "decoded_output: $DecodedOut"
if (Test-Path $DecodedOut) { $Lines += "decoded_size:   " + (Get-Item $DecodedOut).Length; $Lines += "decoded_md5:    " + (Get-MD5 $DecodedOut) }
$Lines += "renamed_copy_at_dest: $RenamedCopyAtDest"
if (Test-Path $RenamedCopyAtDest) { $Lines += "renamed_copy_size: " + (Get-Item $RenamedCopyAtDest).Length; $Lines += "renamed_copy_md5:  " + (Get-MD5 $RenamedCopyAtDest) }
$Lines += "stderr_file:   $ErrPath"
if (Test-Path $ErrPath) {
  $preview = ""
  try { $preview = (Get-Content $ErrPath -Raw); if ($preview.Length -gt 2000){ $preview=$preview.Substring(0,2000) } } catch {}
  if ($preview) { $Lines += "--- stderr preview (first 2000 chars) ---"; $Lines += $preview }
}
[IO.File]::WriteAllLines($LogPath,$Lines)

# Notify end
if (($ExitCode -eq 0) -and (Test-Path $DecodedOut) -and ((Get-Item $DecodedOut).Length -gt 0)) {
  [System.Windows.Forms.MessageBox]::Show("Success!`nDecoded:`n$DecodedOut`n`nCopied temp as:`n$RenamedCopyAtDest`n`nLogs:`n$LogPath","JSXER Decoder",'OK','Information')|Out-Null
} else {
  [System.Windows.Forms.MessageBox]::Show("Finished with issues.`nCheck logs:`n$LogPath`n`nErrors:`n$ErrPath","JSXER Decoder",'OK','Warning')|Out-Null
}
'@

# Inject payloads
$Wrapper = $Wrapper.Replace('__B64_JSXER__', $b64_jsxer)
$Wrapper = $Wrapper.Replace('__B64_DLL__',   $b64_dll)
$Wrapper = $Wrapper.Replace('__B64_LIB__',   $b64_lib)

# Write wrapper to disk
$WrapperFile = Join-Path $Root 'jsxer-packed-wrapper.ps1'
Set-Content -Path $WrapperFile -Value $Wrapper -Encoding UTF8
Write-Host "Generated wrapper: $WrapperFile"

# Ensure PS2EXE
if (-not (Get-Module -ListAvailable -Name PS2EXE)) {
  try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}
  Install-Module PS2EXE -Scope CurrentUser -Force -Confirm:$false
}

# --- Compile single-file EXE (timestamped name, no overwrite), with ICON if available ---
$Stamp   = (Get-Date -Format 'yyyyMMdd_HHmmss')
$OutExe  = Join-Path $Root ("JSXER-Decoder_{0}.exe" -f $Stamp)
$IconIco = Join-Path $Root 'icon_jsxer.ico'

# Find the cmdlet name we have
$cmdName = if (Get-Command -Name Invoke-PS2EXE -ErrorAction SilentlyContinue) { 'Invoke-PS2EXE' }
           elseif (Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue) { 'Invoke-ps2exe' }
           else { $null }
if (-not $cmdName) { Write-Host "ERROR: PS2EXE not found." -ForegroundColor Red; exit 1 }

# Discover available parameters on this version
$paramSet = (Get-Command -Name $cmdName).Parameters.Keys

# Build base args via splatting (guaranteed strings)
$baseArgs = @{
  InputFile   = [string]$WrapperFile
  OutputFile  = [string]$OutExe
  NoConsole   = $true
  STA         = $true
  Title       = 'JSXER Decoder'
  Description = 'Single-file GUI wrapper; embeds jsxer.exe + dll + lib; logs under <name>-JsxerLogs; preserves original; custom header'
}

# Add icon parameter if supported and file exists
if (Test-Path $IconIco) {
  if ($paramSet -contains 'IconFile') {
    $baseArgs['IconFile'] = [string]$IconIco
  } elseif ($paramSet -contains 'Icon') {
    $baseArgs['Icon'] = [string]$IconIco
  }
}

# Call the cmdlet with splatting (no positional/array confusion)
& $cmdName @baseArgs

Write-Host ""
Write-Host "Done."
Write-Host ("Single-file EXE: {0}" -f $OutExe)
if (Test-Path $IconIco) {
  Write-Host ("Icon used: {0}" -f $IconIco)
} else {
  Write-Host "Icon used: none (icon_jsxer.ico not found)"
}
