# ==============================================================================
# Manage-WindowsInsider.ps1
# Premium Restoration & Configuration Tool for Windows Insider Program
# Optimized for Custom OS Build environments (AtlasOS / Ghost Spectre)
# ==============================================================================

$ErrorActionPreference = "Stop"

# Clear host and show high-quality ASCII header
Clear-Host
Write-Host -ForegroundColor Cyan @"
==========================================================================
   _   _   _  _ _ __  ___   ___   ___  _   _   _ ___ ___  ___   _   _ 
  /_\ | | | |/ / |  \/  |  / __| / _ \| | | | / /_ _/ _ \/ __| /_\ | |
 / _ \| |_| ' <| | |\/| |  \__ \| (_) | |_| ' < | | (_) \__ \/ _ \| |
/_/ \_\___|_|\_\_|_|  |_|  |___/ \___/ \___|_|\_\___\___/|___/_/ \_\_|
==========================================================================
              Windows Insider Restoration & Management Utility
          Supports Online MSA & Offline Bypass (AtlasOS / Ghost Spectre)
==========================================================================
"@

# ------------------------------------------------------------------------------
# 1. ELEVATION CHECK
# ------------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n[!] ERROR: Administrative privileges are required to run this utility." -ForegroundColor Red
    Write-Host "[*] Please re-launch PowerShell as Administrator." -ForegroundColor Yellow
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    [void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Exit
}

# ------------------------------------------------------------------------------
# 2. DEFINITIONS & CONSTANTS
# ------------------------------------------------------------------------------
$SELFHOST_PATH = "HKLM:\SOFTWARE\Microsoft\WindowsSelfHost"
$APPLICABILITY_PATH = "$SELFHOST_PATH\Applicability"
$UI_PATH = "$SELFHOST_PATH\UI"
$SELECTION_PATH = "$UI_PATH\Selection"
$EXPLORER_POLICIES_PATH = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$DATACOLLECTION_POLICIES_PATH = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
$DATACOLLECTION_SYSTEM_PATH = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
$WINDOWSUPDATE_POLICIES_PATH = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# ------------------------------------------------------------------------------
# 3. HELPER FUNCTIONS
# ------------------------------------------------------------------------------

function Write-Success ($msg) {
    Write-Host "[+] SUCCESS: $msg" -ForegroundColor Green
}

function Write-Info ($msg) {
    Write-Host "[*] INFO: $msg" -ForegroundColor Cyan
}

function Write-WarningMsg ($msg) {
    Write-Host "[!] WARNING: $msg" -ForegroundColor Yellow
}

function Write-ErrorMsg ($msg) {
    Write-Host "[-] ERROR: $msg" -ForegroundColor Red
}

function Set-RegistryValue ($path, $name, $value, $type) {
    try {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
        return $true
    } catch {
        Write-ErrorMsg "Failed to set Registry key: $path\$name to $value ($type)"
        return $false
    }
}

function Remove-RegistryValue ($path, $name) {
    try {
        if (Test-Path $path) {
            Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction SilentlyContinue | Out-Null
        }
        return $true
    } catch {
        return $false
    }
}

function Set-ServiceState ($serviceName, $startupType, $action) {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        Write-WarningMsg "Service '$serviceName' was not found on this system. It might have been aggressively stripped."
        return $false
    }

    try {
        # Set Startup Type
        Set-Service -Name $serviceName -StartupType $startupType -ErrorAction Stop
        
        # Apply Action (Start/Stop)
        if ($action -eq "Start") {
            if ($service.Status -ne "Running") {
                Start-Service -Name $serviceName -ErrorAction Stop
            }
        } elseif ($action -eq "Stop") {
            if ($service.Status -eq "Running") {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
            }
        }
        Write-Success "Service '$serviceName' startup configured as '$startupType' and status is '$action'."
        return $true
    } catch {
        Write-ErrorMsg "Failed to configure service '$serviceName' to '$startupType' / '$action'. Exception: $_"
        return $false
    }
}

function Backup-SettingsPageVisibility {
    if (Test-Path $EXPLORER_POLICIES_PATH) {
        $val = Get-ItemProperty -Path $EXPLORER_POLICIES_PATH -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue
        if ($val -and ($null -ne $val.SettingsPageVisibility)) {
            # Only backup if a backup does not already exist
            $backup = Get-ItemProperty -Path $EXPLORER_POLICIES_PATH -Name "SettingsPageVisibility_Backup_InsiderScript" -ErrorAction SilentlyContinue
            if (-not $backup) {
                Set-RegistryValue $EXPLORER_POLICIES_PATH "SettingsPageVisibility_Backup_InsiderScript" $val.SettingsPageVisibility "String"
                Write-Info "Backed up existing SettingsPageVisibility policies."
            }
        }
    }
}

function Unhide-InsiderPage {
    Backup-SettingsPageVisibility
    
    # 1. Modify the Explorer policy restricting settings page visibility
    if (Test-Path $EXPLORER_POLICIES_PATH) {
        $val = Get-ItemProperty -Path $EXPLORER_POLICIES_PATH -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue
        if ($val -and ($null -ne $val.SettingsPageVisibility)) {
            $visibility = $val.SettingsPageVisibility
            if ($visibility -match "windowsinsider") {
                # Parse and filter out windowsinsider
                $parts = $visibility -split ":"
                $mode = $parts[0] # "hide" or "showonly"
                $pages = $parts[1] -split ";"
                $filtered = $pages | Where-Object { $_ -ne "windowsinsider" }
                
                if ($filtered.Count -eq 0 -or ($filtered.Count -eq 1 -and $filtered[0] -eq "")) {
                    Remove-RegistryValue $EXPLORER_POLICIES_PATH "SettingsPageVisibility"
                    Write-Success "Cleared restriction policy SettingsPageVisibility entirely (it only contained windowsinsider)."
                } else {
                    $newVal = $mode + ":" + ($filtered -join ";")
                    Set-RegistryValue $EXPLORER_POLICIES_PATH "SettingsPageVisibility" $newVal "String"
                    Write-Success "Removed 'windowsinsider' from SettingsPageVisibility policy filter."
                }
            }
        }
    }

    # 2. Set HideInsiderPage = 0 under SelfHost UI
    $UI_Visibility_Path = "$UI_PATH\Visibility"
    Set-RegistryValue $UI_Visibility_Path "HideInsiderPage" 0 "DWord"
    Write-Success "Ensured Insider page is set to Visible in UI/Visibility registry."
}

function Restore-SettingsPageVisibility {
    if (Test-Path $EXPLORER_POLICIES_PATH) {
        $backup = Get-ItemProperty -Path $EXPLORER_POLICIES_PATH -Name "SettingsPageVisibility_Backup_InsiderScript" -ErrorAction SilentlyContinue
        if ($backup -and ($null -ne $backup.SettingsPageVisibility_Backup_InsiderScript)) {
            Set-RegistryValue $EXPLORER_POLICIES_PATH "SettingsPageVisibility" $backup.SettingsPageVisibility_Backup_InsiderScript "String"
            Remove-RegistryValue $EXPLORER_POLICIES_PATH "SettingsPageVisibility_Backup_InsiderScript"
            Write-Success "Restored original system SettingsPageVisibility policy."
        } else {
            # If no backup existed, AtlasOS/Ghost Spectre probably had none or hid it by default.
            # Usually, they write "hide:windowsinsider" to block it. We will write it back to hide it if no backup was found.
            Set-RegistryValue $EXPLORER_POLICIES_PATH "SettingsPageVisibility" "hide:windowsinsider" "String"
            Write-Success "Re-applied 'hide:windowsinsider' to lock the settings page visibility."
        }
    }
    
    # Re-hide inside SelfHost UI
    $UI_Visibility_Path = "$UI_PATH\Visibility"
    Set-RegistryValue $UI_Visibility_Path "HideInsiderPage" 1 "DWord"
    Write-Success "Re-hid Windows Insider page under UI/Visibility registry."
}

# ------------------------------------------------------------------------------
# 4. CORE FEATURES
# ------------------------------------------------------------------------------

# Enables services and policies required for basic Windows Insider function
function Enable-CoreServicesAndPolicies {
    Write-Host "`n>>> [STEP 1] Re-Enabling Core System Services..." -ForegroundColor Cyan
    
    # DiagTrack (Telemetry) is absolutely required for Microsoft to send Insider builds
    Set-ServiceState "DiagTrack" "Automatic" "Start" | Out-Null
    
    # wisvc (Windows Insider Service)
    Set-ServiceState "wisvc" "Manual" "Start" | Out-Null
    
    # wuauserv (Windows Update)
    Set-ServiceState "wuauserv" "Manual" "Start" | Out-Null
    
    # UsoSvc (Update Orchestrator)
    Set-ServiceState "UsoSvc" "Automatic" "Start" | Out-Null

    Write-Host "`n>>> [STEP 2] Unblocking System Telemetry & Policies..." -ForegroundColor Cyan
    
    # Configure Telemetry level to "Full / Optional" (3) which is mandated for Windows Insider
    Set-RegistryValue $DATACOLLECTION_POLICIES_PATH "AllowTelemetry" 3 "DWord" | Out-Null
    Set-RegistryValue $DATACOLLECTION_SYSTEM_PATH "AllowTelemetry" 3 "DWord" | Out-Null
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" "EventConsentState" 1 "DWord" | Out-Null
    Set-RegistryValue $APPLICABILITY_PATH "DiagnosticContentLevel" 0 "DWord" | Out-Null
    Write-Success "Diagnostic/Telemetry data collection level has been elevated to 'Full' (Value: 3)."

    Write-Host "`n>>> [STEP 3] Enabling Boot Flight Signing..." -ForegroundColor Cyan
    try {
        # Enable flight signing so pre-release kernel/drivers signature verification passes
        $bcdResult = bcdedit /set flightsigning on 2>&1
        Write-Success "Boot Flight Signing has been enabled via BCDEDIT."
    } catch {
        Write-WarningMsg "Failed to toggle Flight Signing via BCDEDIT. This can happen if Secure Boot or BitLocker restricts it. Error: $_"
    }
    Write-Host "`n>>> [STEP 4] Restoring Settings Page Visibility..." -ForegroundColor Cyan
    Unhide-InsiderPage

    Write-Host "`n>>> [STEP 4.5] Configuring Windows Update and Telemetry Policies..." -ForegroundColor Cyan
    # Elevate MaxTelemetryAllowed to 3 so telemetry isn't capped at 0/Basic by custom OS optimization
    Set-RegistryValue $DATACOLLECTION_SYSTEM_PATH "MaxTelemetryAllowed" 3 "DWord" | Out-Null
    
    # Explicitly write GPO policies to allow preview builds (essential for stripped custom OS environments)
    Set-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "ManagePreviewBuilds" 1 "DWord" | Out-Null
    Set-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "ManagePreviewBuildsPolicyValue" 1 "DWord" | Out-Null
    Write-Success "Explicitly enabled preview builds policy (ManagePreviewBuilds = 1, ManagePreviewBuildsPolicyValue = 1)."

    # Remove Windows Update GPO Blocks that lock updates to a specific version
    if (Test-Path $WINDOWSUPDATE_POLICIES_PATH) {
        Remove-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "TargetReleaseVersion" | Out-Null
        Remove-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "TargetReleaseVersionInfo" | Out-Null
        Remove-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "ProductVersion" | Out-Null
        Write-Success "Cleared restrictive version lock policies (TargetReleaseVersion)."
    }

    Write-Host "`n>>> [STEP 5] Enabling Windows Update Flighting & Flushing WU Cache..." -ForegroundColor Cyan
    # FlightingEnabled = 1 tells WU to query Microsoft's Insider flight servers (CRITICAL)
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" "FlightingEnabled" 1 "DWord" | Out-Null
    Write-Success "FlightingEnabled set to 1 (WU will now query Insider flight servers)."

    # Flush the Windows Update DataStore cache so WU re-queries from scratch
    try {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service UsoSvc   -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Remove-Item "C:\Windows\SoftwareDistribution\DataStore\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Start-Service UsoSvc   -ErrorAction SilentlyContinue
        Write-Success "Windows Update cache flushed - WU will fetch fresh flight data on next scan."
    } catch {
        Write-WarningMsg "Could not fully flush WU cache: $_"
    }
}

# Standard Option: Re-enable page & services (requires MS account sign-in)
function Option-EnableStandard {
    Write-Host "`n=== OPTION 1: ENABLE WINDOWS INSIDER (STANDARD) ===" -ForegroundColor Yellow
    Write-WarningMsg "This will enable services and make the Insider Program Settings page visible."
    Write-WarningMsg "You will be required to log in with a registered Microsoft Account to join."
    
    Write-Host "`nDo you want to proceed? [Y/N]: " -NoNewline -ForegroundColor White
    $confirm = Read-Host
    if ($confirm -notmatch "^[yY]$") {
        Write-Info "Operation cancelled."
        return
    }

    try {
        Write-Host "`n>>> Resetting Windows Insider SelfHost registry key to purge any custom OS corruption..." -ForegroundColor Cyan
        if (Test-Path $SELFHOST_PATH) {
            Remove-Item -Path $SELFHOST_PATH -Recurse -Force | Out-Null
        }

        Enable-CoreServicesAndPolicies
        
        # Clear any prior SelfHost offline registry locks to allow clean MSA sign-in
        Remove-RegistryValue $SELFHOST_PATH "TestFlags" | Out-Null
        
        Write-Host "`n==========================================================================" -ForegroundColor Green
        Write-Success "Windows Insider Program has been successfully re-enabled!"
        Write-Host "1. Please restart your PC to apply all updates and flight signing." -ForegroundColor Yellow
        Write-Host "2. Go to: Settings > Windows Update > Windows Insider Program to enroll." -ForegroundColor Yellow
        Write-Host "==========================================================================" -ForegroundColor Green
    } catch {
        Write-ErrorMsg "An unexpected error occurred: $_"
    }
}

# Offline Bypass Option: Direct channel enrollment without Microsoft Account
function Option-EnableOffline {
    Write-Host "`n=== OPTION 2: ENABLE WINDOWS INSIDER (OFFLINE BYPASS) ===" -ForegroundColor Yellow
    Write-WarningMsg "This option force-enrolls your local account into a specific channel"
    Write-WarningMsg "without requiring a Microsoft Account sign-in (OfflineInsiderEnroll method)."
    
    Write-Host "`nSelect your target Windows Insider Channel:" -ForegroundColor Cyan
    Write-Host "[1] Experimental Channel (Latest consolidated channel for Dev/Canary)" -ForegroundColor Yellow
    Write-Host "[2] Beta Channel (Recommended for early adopters, fairly stable)" -ForegroundColor Gray
    Write-Host "[3] Release Preview Channel (Near-final builds, safest choice)" -ForegroundColor Gray
    Write-Host "[4] Canary Channel (Legacy - For older systems/builds)" -ForegroundColor DarkGray
    Write-Host "[5] Dev Channel (Legacy - For older systems/builds)" -ForegroundColor DarkGray
    Write-Host "[6] Cancel" -ForegroundColor Gray
    
    Write-Host "`nEnter selection [1-6]: " -NoNewline -ForegroundColor White
    $selection = Read-Host
    
    $channel = ""
    $brl = $null
    $ring = "External"
    $ringId = 11
    $contentType = "Mainline"
    
    switch ($selection) {
        "1" { $channel = "Experimental";   $brl = $null }
        "2" { $channel = "Beta";           $brl = 4 }
        "3" { $channel = "ReleasePreview"; $brl = 8 }
        "4" { $channel = "CanaryChannel";  $brl = $null }
        "5" { $channel = "Dev";            $brl = 2 }
        default {
            Write-Info "Operation cancelled."
            return
        }
    }
    
    Write-Host "`nForce enrolling in the '$channel' Channel offline. Proceeding..." -ForegroundColor Cyan
    
    try {
        Write-Host "`n>>> Resetting Windows Insider SelfHost registry key to purge any custom OS corruption..." -ForegroundColor Cyan
        if (Test-Path $SELFHOST_PATH) {
            Remove-Item -Path $SELFHOST_PATH -Recurse -Force | Out-Null
        }
        
        # Clean up SLS overrides if any
        $SLS_PATH = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SLS\Programs"
        Remove-Item -Path "$SLS_PATH\WUMUDCat" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\Ring$ring" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\RingExternal" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\RingPreview" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\RingInsiderSlow" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\RingInsiderFast" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

        # 1. Enable core components (services, telemetry, visibility, flightsigning)
        Enable-CoreServicesAndPolicies

        # 2. Write SelfHost bypass registry keys (OfflineInsiderEnroll signature)
        Write-Host "`n>>> [STEP 5] Applying Offline SelfHost Bypass Registry Configuration..." -ForegroundColor Cyan
        
        # Orchestrator & SLS Overrides
        Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator" "EnableUUPScan" 1 "DWord" | Out-Null
        Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SLS\Programs\Ring$ring" "Enabled" 1 "DWord" | Out-Null
        Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SLS\Programs\WUMUDCat" "WUMUDCATEnabled" 1 "DWord" | Out-Null
        
        # Applicability Configuration
        Set-RegistryValue $APPLICABILITY_PATH "EnablePreviewBuilds" 2 "DWord" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "IsBuildFlightingEnabled" 1 "DWord" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "IsConfigSettingsFlightingEnabled" 1 "DWord" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "IsConfigExpFlightingEnabled" 0 "DWord" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "TestFlags" 32 "DWord" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "RingId" $ringId "DWord" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "Ring" $ring "String" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "ContentType" $contentType "String" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "BranchName" $channel "String" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "RingBackup" $ring "String" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "RingBackupV2" $ring "String" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "BranchBackup" $channel "String" | Out-Null
        Set-RegistryValue $APPLICABILITY_PATH "UseSettingsExperience" 0 "DWord" | Out-Null

        # UI & Visibility Configuration
        $UI_VISIBILITY_PATH = "$UI_PATH\Visibility"
        Set-RegistryValue $UI_VISIBILITY_PATH "UIHiddenElements" 65535 "DWord" | Out-Null
        Set-RegistryValue $UI_VISIBILITY_PATH "UIDisabledElements" 65535 "DWord" | Out-Null
        Set-RegistryValue $UI_VISIBILITY_PATH "UIServiceDrivenElementVisibility" 0 "DWord" | Out-Null
        Set-RegistryValue $UI_VISIBILITY_PATH "UIErrorMessageVisibility" 192 "DWord" | Out-Null
        Set-RegistryValue $UI_VISIBILITY_PATH "UIHiddenElements_Rejuv" 65534 "DWord" | Out-Null
        Set-RegistryValue $UI_VISIBILITY_PATH "UIDisabledElements_Rejuv" 65535 "DWord" | Out-Null

        # UI Selection Configuration
        Set-RegistryValue $SELECTION_PATH "UIRing" $ring "String" | Out-Null
        Set-RegistryValue $SELECTION_PATH "UIContentType" $contentType "String" | Out-Null
        Set-RegistryValue $SELECTION_PATH "UIBranch" $channel "String" | Out-Null
        Set-RegistryValue $SELECTION_PATH "UIOptin" 1 "DWord" | Out-Null
        Set-RegistryValue $SELECTION_PATH "UIDialogConsent" 0 "DWord" | Out-Null
        Set-RegistryValue $SELECTION_PATH "UIUsage" 26 "DWord" | Out-Null
        Set-RegistryValue $SELECTION_PATH "OptOutState" 25 "DWord" | Out-Null
        Set-RegistryValue $SELECTION_PATH "AdvancedToggleState" 24 "DWord" | Out-Null

        # UI Controllable State
        Set-RegistryValue $UI_PATH "UIControllableState" 0 "DWord" | Out-Null

        # Cache & Accounts Configuration
        Set-RegistryValue "$SELFHOST_PATH\Cache" "PropertyIgnoreList" "AccountsBlob;;CTACBlob;FlightIDBlob;ServiceDrivenActionResults" "String" | Out-Null
        Set-RegistryValue "$SELFHOST_PATH\Cache" "RequestedCTACAppIds" "WU;FSS" "String" | Out-Null
        Set-RegistryValue "$SELFHOST_PATH\Account" "SupportedTypes" 3 "DWord" | Out-Null
        Set-RegistryValue "$SELFHOST_PATH\Account" "Status" 8 "DWord" | Out-Null

        # ClientState Configuration
        $CS_PATH = "$SELFHOST_PATH\ClientState"
        Set-RegistryValue $CS_PATH "AllowFSSCommunications" 0 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "UICapabilities" 1 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "IgnoreConsolidation" 1 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "MsaUserTicketHr" 0 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "MsaDeviceTicketHr" 0 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "ValidateOnlineHr" 0 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "LastHR" 0 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "ErrorState" 0 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "PilotInfoRing" 3 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "RegistryAllowlistVersion" 4 "DWord" | Out-Null
        Set-RegistryValue $CS_PATH "FileAllowlistVersion" 1 "DWord" | Out-Null

        # Setup & Upgrade Bypasses
        Set-RegistryValue "HKLM:\SYSTEM\Setup\WindowsUpdate" "AllowWindowsUpdate" 1 "DWord" | Out-Null
        Set-RegistryValue "HKLM:\SYSTEM\Setup\MoSetup" "AllowUpgradesWithUnsupportedTPMOrCPU" 1 "DWord" | Out-Null
        Set-RegistryValue "HKLM:\SYSTEM\Setup\LabConfig" "BypassRAMCheck" 1 "DWord" | Out-Null
        Set-RegistryValue "HKLM:\SYSTEM\Setup\LabConfig" "BypassSecureBootCheck" 1 "DWord" | Out-Null
        Set-RegistryValue "HKLM:\SYSTEM\Setup\LabConfig" "BypassStorageCheck" 1 "DWord" | Out-Null
        Set-RegistryValue "HKLM:\SYSTEM\Setup\LabConfig" "BypassTPMCheck" 1 "DWord" | Out-Null
        Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\PCHC" "UpgradeEligibility" 1 "DWord" | Out-Null

        # Sticky Message Configuration
        $stickyJson = '{"Message":"Device Enrolled Using OfflineInsiderEnroll","LinkTitle":"","LinkUrl":"","DynamicXaml":"<StackPanel xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><TextBlock Style=\"{StaticResource BodyTextBlockStyle }\">This device has been enrolled to the Windows Insider program using OfflineInsiderEnroll. If you want to change settings of the enrollment or stop receiving Windows Insider builds, please use the script.</TextBlock></StackPanel>","Severity":0}'
        Set-RegistryValue "$UI_PATH\Strings" "StickyMessage" $stickyJson "String" | Out-Null

        # BranchReadinessLevel Configuration (Crucial for Dev, Beta, RP)
        if ($null -ne $brl) {
            Set-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "BranchReadinessLevel" $brl "DWord" | Out-Null
            Write-Success "BranchReadinessLevel set to $brl for channel $channel."
        } else {
            Remove-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "BranchReadinessLevel" | Out-Null
        }
        
        Write-Success "Applied SelfHost bypass parameters for the '$channel' channel."

        Write-Host "`n==========================================================================" -ForegroundColor Green
        Write-Success "Offline Windows Insider enrollment completed successfully!"
        Write-Host "1. A SYSTEM REBOOT IS MANDATORY to reload flight signing and update services." -ForegroundColor Yellow
        Write-Host "2. After reboot, go to Settings > Windows Update and click 'Check for Updates'." -ForegroundColor Yellow
        Write-Host "==========================================================================" -ForegroundColor Green
    } catch {
        Write-ErrorMsg "Failed to apply offline enrollment. Exception: $_"
    }
}

# Restore Option: Reverts changes, disables services, locks UI down again
function Option-RestoreOriginalState {
    Write-Host "`n=== OPTION 3: RESTORE ORIGINAL STATE (DISABLE & RE-LOCK) ===" -ForegroundColor Yellow
    Write-WarningMsg "This will reverse all adjustments, disable telemetry/diagnostics,"
    Write-WarningMsg "disable the Windows Insider service, and re-hide the Settings page."
    Write-WarningMsg "This restores your highly-optimized AtlasOS/Ghost Spectre baseline."
    
    Write-Host "`nDo you want to proceed? [Y/N]: " -NoNewline -ForegroundColor White
    $confirm = Read-Host
    if ($confirm -notmatch "^[yY]$") {
        Write-Info "Operation cancelled."
        return
    }

    try {
        Write-Host "`n>>> [STEP 1] Re-locking UI & Restoring Visibility Policies..." -ForegroundColor Cyan
        Restore-SettingsPageVisibility
        
        Write-Host "`n>>> [STEP 2] Disabling Flight Signing..." -ForegroundColor Cyan
        try {
            bcdedit /set flightsigning off | Out-Null
            Write-Success "Boot Flight Signing has been disabled."
        } catch {
            Write-WarningMsg "Failed to toggle Flight Signing off. Secure boot or permissions might block it."
        }

        Write-Host "`n>>> [STEP 3] Cleaning up Windows SelfHost Registry Entries..." -ForegroundColor Cyan
        if (Test-Path $SELFHOST_PATH) {
            Remove-Item -Path $SELFHOST_PATH -Recurse -Force | Out-Null
            Write-Success "SelfHost configurations cleared."
        }

        Write-Host "`n>>> [STEP 3.5] Cleaning up SLS and Update Orchestrator Overrides..." -ForegroundColor Cyan
        $SLS_PATH = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SLS\Programs"
        Remove-Item -Path "$SLS_PATH\WUMUDCat" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\RingExternal" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\RingPreview" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\RingInsiderSlow" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "$SLS_PATH\RingInsiderFast" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        
        # Clean up Setup bypasses
        Remove-RegistryValue "HKLM:\SYSTEM\Setup\WindowsUpdate" "AllowWindowsUpdate" | Out-Null
        Remove-RegistryValue "HKLM:\SYSTEM\Setup\MoSetup" "AllowUpgradesWithUnsupportedTPMOrCPU" | Out-Null
        Remove-RegistryValue "HKLM:\SYSTEM\Setup\LabConfig" "BypassRAMCheck" | Out-Null
        Remove-RegistryValue "HKLM:\SYSTEM\Setup\LabConfig" "BypassSecureBootCheck" | Out-Null
        Remove-RegistryValue "HKLM:\SYSTEM\Setup\LabConfig" "BypassStorageCheck" | Out-Null
        Remove-RegistryValue "HKLM:\SYSTEM\Setup\LabConfig" "BypassTPMCheck" | Out-Null
        Remove-RegistryValue "HKCU:\SOFTWARE\Microsoft\PCHC" "UpgradeEligibility" | Out-Null

        Write-Host "`n>>> [STEP 4] Reverting Telemetry & Diagnostics Policies..." -ForegroundColor Cyan
        # Revert telemetry settings back to secure/zero level to match optimized systems
        Set-RegistryValue $DATACOLLECTION_POLICIES_PATH "AllowTelemetry" 0 "DWord" | Out-Null
        Set-RegistryValue $DATACOLLECTION_SYSTEM_PATH "AllowTelemetry" 0 "DWord" | Out-Null
        Set-RegistryValue $DATACOLLECTION_SYSTEM_PATH "MaxTelemetryAllowed" 0 "DWord" | Out-Null
        Remove-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" "EventConsentState" | Out-Null
        Remove-RegistryValue $APPLICABILITY_PATH "DiagnosticContentLevel" | Out-Null
        
        # Re-apply Windows Update preview builds blocks if restoring to original optimized state
        if (Test-Path $WINDOWSUPDATE_POLICIES_PATH) {
            Set-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "ManagePreviewBuilds" 1 "DWord" | Out-Null
            Set-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "ManagePreviewBuildsPolicyValue" 0 "DWord" | Out-Null
            Remove-RegistryValue $WINDOWSUPDATE_POLICIES_PATH "BranchReadinessLevel" | Out-Null
        }
        Write-Success "Telemetry & Windows Update policies successfully set back to 'Disabled' (0)."

        Write-Host "`n>>> [STEP 5] Stopping and Disabling Services..." -ForegroundColor Cyan
        # Stop and Disable wisvc (Insider)
        Set-ServiceState "wisvc" "Disabled" "Stop" | Out-Null
        
        # Stop and Disable DiagTrack (Telemetry)
        Set-ServiceState "DiagTrack" "Disabled" "Stop" | Out-Null
        
        # Note: We do NOT disable wuauserv (Windows Update) or UsoSvc automatically,
        # since standard updates might be required. But we restore the Windows Insider baseline.

        Write-Host "`n==========================================================================" -ForegroundColor Green
        Write-Success "Original optimized state restored perfectly!"
        Write-Host "A system restart is recommended to fully unload services and update paths." -ForegroundColor Yellow
        Write-Host "==========================================================================" -ForegroundColor Green
    } catch {
        Write-ErrorMsg "An error occurred while restoring settings: $_"
    }
}

# Diagnostic Option: Review current configuration of services and keys
function Option-ShowDiagnostics {
    Write-Host "`n=== SYSTEM DIAGNOSTIC RUN ===" -ForegroundColor Yellow
    
    # Check Services
    Write-Host "`n--- Services Status ---" -ForegroundColor Cyan
    $services = @("wisvc", "DiagTrack", "wuauserv", "UsoSvc")
    foreach ($srvName in $services) {
        $srv = Get-Service -Name $srvName -ErrorAction SilentlyContinue
        if ($null -eq $srv) {
            Write-Host "$($srvName): NOT FOUND (Stripped)" -ForegroundColor Red
        } else {
            $color = if ($srv.Status -eq "Running") { "Green" } else { "DarkYellow" }
            $startup = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$srvName'").StartMode
            Write-Host "$($srvName): Status = $($srv.Status) | StartupMode = $startup" -ForegroundColor $color
        }
    }
    
    # Check Telemetry GPOs
    Write-Host "`n--- Telemetry & GPO Policies ---" -ForegroundColor Cyan
    $telGPO = Get-ItemProperty -Path $DATACOLLECTION_POLICIES_PATH -Name "AllowTelemetry" -ErrorAction SilentlyContinue
    $telSys = Get-ItemProperty -Path $DATACOLLECTION_SYSTEM_PATH -Name "AllowTelemetry" -ErrorAction SilentlyContinue
    $maxTel = Get-ItemProperty -Path $DATACOLLECTION_SYSTEM_PATH -Name "MaxTelemetryAllowed" -ErrorAction SilentlyContinue
    
    $tgVal = if ($telGPO) { $telGPO.AllowTelemetry } else { "Not Set" }
    $tsVal = if ($telSys) { $telSys.AllowTelemetry } else { "Not Set" }
    $mtVal = if ($maxTel) { $maxTel.MaxTelemetryAllowed } else { "Not Set" }
    
    Write-Host "Telemetry Policy (GPO): $tgVal" -ForegroundColor (if ($tgVal -eq 3) { "Green" } else { "Gray" })
    Write-Host "Telemetry Policy (System): $tsVal" -ForegroundColor (if ($tsVal -eq 3) { "Green" } else { "Gray" })
    Write-Host "Max Telemetry Allowed: $mtVal" -ForegroundColor (if ($mtVal -eq 3 -or $mtVal -eq "Not Set") { "Green" } else { "Red" })

    # Check Windows Update policies
    Write-Host "`n--- Windows Update GPO Policies ---" -ForegroundColor Cyan
    if (Test-Path $WINDOWSUPDATE_POLICIES_PATH) {
        $mpb = Get-ItemProperty -Path $WINDOWSUPDATE_POLICIES_PATH -Name "ManagePreviewBuilds" -ErrorAction SilentlyContinue
        $mpbp = Get-ItemProperty -Path $WINDOWSUPDATE_POLICIES_PATH -Name "ManagePreviewBuildsPolicyValue" -ErrorAction SilentlyContinue
        $trv = Get-ItemProperty -Path $WINDOWSUPDATE_POLICIES_PATH -Name "TargetReleaseVersion" -ErrorAction SilentlyContinue
        
        $mpbVal = if ($mpb) { $mpb.ManagePreviewBuilds } else { "Not Set" }
        $mpbpVal = if ($mpbp) { $mpbp.ManagePreviewBuildsPolicyValue } else { "Not Set" }
        $trvVal = if ($trv) { $trv.TargetReleaseVersion } else { "Not Set" }
        
        Write-Host "ManagePreviewBuilds: $mpbVal" -ForegroundColor (if ($mpbVal -eq 1 -or $mpbVal -eq "Not Set") { "Green" } else { "Red" })
        Write-Host "ManagePreviewBuildsPolicyValue: $mpbpVal" -ForegroundColor (if ($mpbpVal -eq 1 -or $mpbpVal -eq "Not Set") { "Green" } else { "Red" })
        Write-Host "TargetReleaseVersion Lock: $trvVal" -ForegroundColor (if ($trvVal -eq "Not Set") { "Green" } else { "Yellow" })
    } else {
        Write-Host "Windows Update Policy key does not exist (No Restrictions)." -ForegroundColor Green
    }
    
    # Check UI visibility
    Write-Host "`n--- UI Settings Page Visibility ---" -ForegroundColor Cyan
    $exploreVal = Get-ItemProperty -Path $EXPLORER_POLICIES_PATH -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue
    $evVal = if ($exploreVal) { $exploreVal.SettingsPageVisibility } else { "None (All pages visible)" }
    Write-Host "SettingsPageVisibility Policy: $evVal" -ForegroundColor (if ($evVal -match "windowsinsider") { "Red" } else { "Green" })
    
    $selfHostUI = Get-ItemProperty -Path "$UI_PATH\Visibility" -Name "HideInsiderPage" -ErrorAction SilentlyContinue
    $shVal = if ($selfHostUI) { $selfHostUI.HideInsiderPage } else { "Not Set" }
    Write-Host "HideInsiderPage Registry Override: $shVal" -ForegroundColor (if ($shVal -eq 1) { "Red" } else { "Green" })

    # Check SelfHost Configuration
    Write-Host "`n--- SelfHost Active Config ---" -ForegroundColor Cyan
    $tf = Get-ItemProperty -Path $SELFHOST_PATH -Name "TestFlags" -ErrorAction SilentlyContinue
    $tfVal = if ($tf) { "0x" + "{0:X}" -f $tf.TestFlags } else { "Not Set" }
    Write-Host "SelfHost TestFlags: $tfVal" -ForegroundColor (if ($tfVal -eq "0x20") { "Green" } else { "Gray" })
    
    if (Test-Path $APPLICABILITY_PATH) {
        $appBranch = Get-ItemProperty -Path $APPLICABILITY_PATH -Name "BranchName" -ErrorAction SilentlyContinue
        $appRing = Get-ItemProperty -Path $APPLICABILITY_PATH -Name "Ring" -ErrorAction SilentlyContinue
        $abVal = if ($appBranch) { $appBranch.BranchName } else { "Not Set" }
        $arVal = if ($appRing) { $appRing.Ring } else { "Not Set" }
        Write-Host "Registered Branch: $abVal | Ring: $arVal" -ForegroundColor (if ($abVal -ne "Not Set") { "Green" } else { "Gray" })
    } else {
        Write-Host "Applicability key does not exist." -ForegroundColor Gray
    }
    
    Write-Host "`n---------------------------------------------------"
    Write-Host "Press any key to return to menu..." -ForegroundColor DarkGray
    [void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ------------------------------------------------------------------------------
# 5. MAIN MENU LOOP
# ------------------------------------------------------------------------------
function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host "              Windows Insider Restoration & Management Utility            " -ForegroundColor Cyan
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "   [1] Enable Windows Insider (Standard - Online MS Account)" -ForegroundColor Yellow
        Write-Host "   [2] Enable Windows Insider (Offline Bypass - No MS Account Required)" -ForegroundColor Yellow
        Write-Host "   [3] Restore Original State (Disable & Re-lock to Optimized Baseline)" -ForegroundColor Yellow
        Write-Host "   [4] Check Current Configuration Diagnostics" -ForegroundColor Cyan
        Write-Host "   [5] Exit" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Enter Selection [1-5]: " -NoNewline -ForegroundColor White
        $choice = Read-Host
        
        switch ($choice) {
            "1" { Option-EnableStandard }
            "2" { Option-EnableOffline }
            "3" { Option-RestoreOriginalState }
            "4" { Option-ShowDiagnostics }
            "5" { 
                Write-Host "`nThank you for using the utility. Exiting..." -ForegroundColor Cyan
                Start-Sleep -Seconds 1
                return 
            }
            default {
                Write-Host "`nInvalid selection. Please enter a value between 1 and 5." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Run the utility menu
Show-Menu
