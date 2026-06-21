# a11_devicetest.ps1 — A11-D2 USER-GATE device-test PRE-FLIGHT helper.
#
# Dot-source it, then call the functions:
#     . .\scripts\a11_devicetest.ps1
#
# This script ONLY automates the mechanical pre-flight + evidence capture the
# A11 runbook (docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md) calls for:
#   • list devices
#   • clean-uninstall the 3 IgniRelay package ids (true clean install)
#   • install the debug APK
#   • clear logcat / launch the app
#   • screenshot + logcat capture into tmp/a11-evidence/<timestamp>/
#   • list packages and flag the legacy bare `network.ignirelay`
#
# IT DOES NOT — and must not — judge or record PASS/FAIL. That verdict is the
# Owner's alone (USER-GATE). No function here writes to the runbook result
# table or prints a pass/fail conclusion.
#
# Created: A11-runbook-prep (docs/script only — no app code touched).
#
# Note: dot-sourcing runs in the caller's scope, so this script deliberately
# does NOT mutate session state (no $ErrorActionPreference change). Functions
# that must hard-fail (e.g. missing APK) `throw` explicitly.

# Resolve repo paths from this script's location so cwd doesn't matter.
$script:A11AppDir  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path           # ignirelay_app
$script:A11RepoDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path        # repo root
$script:A11DebugApk = Join-Path $A11AppDir 'build\app\outputs\flutter-apk\app-debug.apk'

# The package ids that must be cleared for a true clean install tonight:
#   • network.ignirelay            — legacy bare id (pre-rename); must NOT remain
#   • network.ignirelay.field      — current app id
#   • network.ignirelay.field.test — instrumentation id from connectedDebugAndroidTest
$script:A11Packages   = @('network.ignirelay', 'network.ignirelay.field', 'network.ignirelay.field.test')
$script:A11MainPkg    = 'network.ignirelay.field'
$script:A11LegacyPkg  = 'network.ignirelay'

# Evidence directory for the current session (set by New-A11Evidence).
$global:A11_EVID = $null

function New-A11Evidence {
  <# Create a fresh tmp/a11-evidence/<timestamp>/ dir and remember it. #>
  $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
  $dir = Join-Path $A11RepoDir "tmp\a11-evidence\$stamp"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $global:A11_EVID = $dir
  Write-Host "evidence dir = $dir"
  return $dir
}

function Assert-A11Evidence {
  if (-not $global:A11_EVID) { New-A11Evidence | Out-Null }
}

function Get-A11Devices {
  <# adb devices -l #>
  adb devices -l
}

function Clear-A11OldPackages {
  <# Uninstall ALL three IgniRelay package ids → true clean slate. A package
     that is not installed returns "Failure" which is expected and ignored. #>
  param([Parameter(Mandatory)] [string] $Serial)
  foreach ($pkg in $A11Packages) {
    Write-Host "uninstall $pkg from $Serial ..."
    try { adb -s $Serial uninstall $pkg | Out-Host } catch { Write-Host "  (not installed: $pkg)" }
  }
}

function Install-A11Apk {
  <# Install the debug APK (build it first with: flutter build apk --debug). #>
  param(
    [Parameter(Mandatory)] [string] $Serial,
    [string] $Apk = $script:A11DebugApk
  )
  if (-not (Test-Path $Apk)) {
    throw "APK not found: $Apk  (run: cd $A11AppDir; flutter build apk --debug)"
  }
  Write-Host "install $Apk -> $Serial ..."
  adb -s $Serial install $Apk | Out-Host
}

function Reset-A11Device {
  <# One-shot CLEAN INSTALL for tonight: uninstall all 3 ids, install fresh,
     then verify packages. A fresh install starts with no app data, so no
     restored ciphertext (allowBackup=false) and no stale HAZARD/DB rows. #>
  param(
    [Parameter(Mandatory)] [string] $Serial,
    [string] $Apk = $script:A11DebugApk
  )
  Clear-A11OldPackages -Serial $Serial
  Install-A11Apk -Serial $Serial -Apk $Apk
  Get-A11Packages -Serial $Serial
}

function Clear-A11Logcat {
  param([Parameter(Mandatory)] [string] $Serial)
  adb -s $Serial logcat -c
  Write-Host "logcat cleared on $Serial"
}

function Start-A11App {
  param([Parameter(Mandatory)] [string] $Serial)
  adb -s $Serial shell monkey -p $A11MainPkg -c android.intent.category.LAUNCHER 1 | Out-Host
}

function Get-A11Shot {
  <# Screenshot -> tmp/a11-evidence/<stamp>/<name>.png #>
  param(
    [Parameter(Mandatory)] [string] $Serial,
    [Parameter(Mandatory)] [string] $Name
  )
  Assert-A11Evidence
  $remote = "/sdcard/a11_$Name.png"
  adb -s $Serial shell screencap -p $remote
  $local = Join-Path $global:A11_EVID "$Name.png"
  adb -s $Serial pull $remote $local | Out-Null
  adb -s $Serial shell rm $remote
  Write-Host "saved $local"
}

function Save-A11Logcat {
  <# Snapshot the current logcat buffer (flutter:V *:S) into evidence. Run this
     after the action you want captured; pair with Clear-A11Logcat before it. #>
  param(
    [Parameter(Mandatory)] [string] $Serial,
    [Parameter(Mandatory)] [string] $Tag
  )
  Assert-A11Evidence
  $out = Join-Path $global:A11_EVID "logcat_$Tag.txt"
  adb -s $Serial logcat -d -v time flutter:V *:S | Out-File -Encoding utf8 $out
  Write-Host "saved $out"
}

function Get-A11Packages {
  <# List installed IgniRelay packages and FLAG the legacy bare id. Expected:
     only network.ignirelay.field (+ optionally .field.test). The bare
     network.ignirelay must NOT appear; if it does it is an old install — clear
     it with Clear-A11OldPackages. Informational only — never a PASS/FAIL. #>
  param([Parameter(Mandatory)] [string] $Serial)
  $pkgs = adb -s $Serial shell pm list packages | Select-String 'ignirelay'
  Write-Host "--- $Serial IgniRelay packages ---"
  $pkgs | ForEach-Object { Write-Host "  $_" }
  $bare = $pkgs | Where-Object { $_ -match "package:$([regex]::Escape($A11LegacyPkg))(`r|`n|$)" }
  if ($bare) {
    Write-Host "WARNING: legacy bare '$A11LegacyPkg' present on $Serial — run Clear-A11OldPackages." -ForegroundColor Yellow
  } else {
    Write-Host "ok: no legacy bare '$A11LegacyPkg' on $Serial"
  }
  if ($global:A11_EVID) {
    $pkgs | Out-File -Encoding utf8 (Join-Path $global:A11_EVID "packages_$Serial.txt")
  }
}

Write-Host ""
Write-Host "A11 device-test pre-flight helper loaded (PRE-FLIGHT ONLY — does NOT judge PASS/FAIL)."
Write-Host "Functions: New-A11Evidence | Get-A11Devices | Reset-A11Device -Serial <s>"
Write-Host "           Clear-A11OldPackages | Install-A11Apk | Get-A11Packages -Serial <s>"
Write-Host "           Clear-A11Logcat | Start-A11App | Get-A11Shot -Serial <s> -Name <n> | Save-A11Logcat -Serial <s> -Tag <t>"
Write-Host "Clean install per device tonight:  Reset-A11Device -Serial `$DEVICE_A   (uninstall x3 -> install -> verify)"
Write-Host ""
