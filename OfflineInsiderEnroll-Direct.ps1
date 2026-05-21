#Requires -RunAsAdministrator
#
# OfflineInsiderEnroll-Direct.ps1
# Direct offline enrollment into Windows Insider Program
# Works on AtlasOS / Ghost Spectre where Settings page is stripped.
# Based on the OfflineInsiderEnroll method by abbodi1406.
#
$ErrorActionPreference = 'Stop'

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   OfflineInsiderEnroll - Direct Channel Enrollment" -ForegroundColor Cyan
Write-Host "   For AtlasOS / Ghost Spectre (No MS Account Required)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This tool bypasses the (stripped) Settings page entirely." -ForegroundColor Gray
Write-Host "It directly writes Insider enrollment data into the registry" -ForegroundColor Gray
Write-Host "and forces Windows Update to fetch Insider Preview builds." -ForegroundColor Gray
Write-Host ""

Write-Host "Select your target Insider Channel:" -ForegroundColor Yellow
Write-Host "  [1] Canary    - Most experimental, cutting-edge features" -ForegroundColor DarkGray
Write-Host "  [2] Dev       - Developer-focused, frequent builds" -ForegroundColor DarkGray
Write-Host "  [3] Beta      - Recommended, relatively stable" -ForegroundColor DarkGray
Write-Host "  [4] Release Preview - Near-final, safest choice" -ForegroundColor DarkGray
Write-Host "  [5] Exit" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Enter selection [1-5]: " -NoNewline -ForegroundColor White
$choice = Read-Host

$channel   = ""
$ringId    = 0
$branchMap = @{
    "1" = @{ Branch = "CanaryChannel";  Ring = "External"; RingId = 11; ContentType = "Mainline" }
    "2" = @{ Branch = "Dev";            Ring = "External"; RingId = 11; ContentType = "Mainline" }
    "3" = @{ Branch = "Beta";           Ring = "External"; RingId = 11; ContentType = "Mainline" }
    "4" = @{ Branch = "ReleasePreview"; Ring = "External"; RingId = 11; ContentType = "Mainline" }
}

if (-not $branchMap.ContainsKey($choice)) {
    Write-Host "Exiting." -ForegroundColor Gray
    exit
}

$cfg = $branchMap[$choice]
Write-Host ""
Write-Host "Enrolling into: $($cfg.Branch) channel..." -ForegroundColor Cyan
Write-Host ""

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Host "  SET  $Name = $Value" -ForegroundColor Green
}

$SH  = "HKLM:\SOFTWARE\Microsoft\WindowsSelfHost"
$APP = "$SH\Applicability"
$UI  = "$SH\UI"
$VIS = "$UI\Visibility"
$SEL = "$UI\Selection"
$CS  = "$SH\ClientState"
$WU  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$DC1 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
$DC2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"

# --- Step 1: Telemetry must be Full (3) ---------------------------------
Write-Host "[1/8] Enabling Full Telemetry..." -ForegroundColor Yellow
Set-Reg $DC1 "AllowTelemetry"      3 "DWord"
Set-Reg $DC2 "AllowTelemetry"      3 "DWord"
Set-Reg $DC2 "MaxTelemetryAllowed" 3 "DWord"

# --- Step 2: Configure WU policies to allow preview builds ----------------
Write-Host "[2/8] Configuring Windows Update policies to allow preview builds..." -ForegroundColor Yellow
Set-Reg $WU "ManagePreviewBuilds"            1 "DWord"
Set-Reg $WU "ManagePreviewBuildsPolicyValue"   1 "DWord"

# Remove version lock blockers
$blockers = @("TargetReleaseVersion","TargetReleaseVersionInfo","ProductVersion")
foreach ($b in $blockers) {
    Remove-ItemProperty -Path $WU -Name $b -Force -ErrorAction SilentlyContinue
    Write-Host "  CLR  $b" -ForegroundColor DarkGray
}

# --- Step 3: Writing Applicability Settings -----------------------------
Write-Host "[3/8] Writing Applicability (Insider channel configuration)..." -ForegroundColor Yellow
Set-Reg $APP "EnablePreviewBuilds"            2                "DWord"
Set-Reg $APP "IsBuildFlightingEnabled"        1                "DWord"
Set-Reg $APP "IsConfigSettingsFlightingEnabled" 1              "DWord"
Set-Reg $APP "IsConfigExpFlightingEnabled"     0              "DWord"
Set-Reg $APP "TestFlags"                      32               "DWord"
Set-Reg $APP "RingId"                         $cfg.RingId      "DWord"
Set-Reg $APP "Ring"                           $cfg.Ring        "String"
Set-Reg $APP "ContentType"                    $cfg.ContentType "String"
Set-Reg $APP "BranchName"                     $cfg.Branch      "String"
Set-Reg $APP "RingBackup"                     $cfg.Ring        "String"
Set-Reg $APP "RingBackupV2"                   $cfg.Ring        "String"
Set-Reg $APP "BranchBackup"                   $cfg.Branch      "String"
Set-Reg $APP "UseSettingsExperience"          0                "DWord"

# --- Step 4: Writing SLS & Orchestrator Overrides -----------------------
Write-Host "[4/8] Writing SLS and Update Orchestrator overrides..." -ForegroundColor Yellow
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator" "EnableUUPScan" 1 "DWord"
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SLS\Programs\Ring$($cfg.Ring)" "Enabled" 1 "DWord"
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SLS\Programs\WUMUDCat" "WUMUDCATEnabled" 1 "DWord"

# --- Step 5: Cache & Accounts settings ----------------------------------
Write-Host "[5/8] Configuring WindowsSelfHost Cache and Accounts parameters..." -ForegroundColor Yellow
Set-Reg "$SH\Cache" "PropertyIgnoreList" "AccountsBlob;;CTACBlob;FlightIDBlob;ServiceDrivenActionResults" "String"
Set-Reg "$SH\Cache" "RequestedCTACAppIds" "WU;FSS" "String"
Set-Reg "$SH\Account" "SupportedTypes" 3 "DWord"
Set-Reg "$SH\Account" "Status" 8 "DWord"

# --- Step 6: Reset ClientState (clearing auth error) --------------------
Write-Host "[6/8] Configuring ClientState parameters..." -ForegroundColor Yellow
Set-Reg $CS "AllowFSSCommunications" 0 "DWord"
Set-Reg $CS "UICapabilities" 1 "DWord"
Set-Reg $CS "IgnoreConsolidation" 1 "DWord"
Set-Reg $CS "MsaUserTicketHr" 0 "DWord"
Set-Reg $CS "MsaDeviceTicketHr" 0 "DWord"
Set-Reg $CS "ValidateOnlineHr" 0 "DWord"
Set-Reg $CS "LastHR" 0 "DWord"
Set-Reg $CS "ErrorState" 0 "DWord"
Set-Reg $CS "PilotInfoRing" 3 "DWord"
Set-Reg $CS "RegistryAllowlistVersion" 4 "DWord"
Set-Reg $CS "FileAllowlistVersion" 1 "DWord"

# --- Step 7: UI Visibility & Selection keys ----------------------------
Write-Host "[7/8] Writing UI Selection & Visibility layout..." -ForegroundColor Yellow
Set-Reg $SEL "UIRing" $cfg.Ring "String"
Set-Reg $SEL "UIContentType" $cfg.ContentType "String"
Set-Reg $SEL "UIBranch" $cfg.Branch "String"
Set-Reg $SEL "UIOptin" 1 "DWord"
Set-Reg $SEL "UIDialogConsent" 0 "DWord"
Set-Reg $SEL "UIUsage" 26 "DWord"
Set-Reg $SEL "OptOutState" 25 "DWord"
Set-Reg $SEL "AdvancedToggleState" 24 "DWord"

Set-Reg $VIS "UIHiddenElements" 65535 "DWord"
Set-Reg $VIS "UIDisabledElements" 65535 "DWord"
Set-Reg $VIS "UIServiceDrivenElementVisibility" 0 "DWord"
Set-Reg $VIS "UIErrorMessageVisibility" 192 "DWord"
Set-Reg $VIS "UIHiddenElements_Rejuv" 65534 "DWord"
Set-Reg $VIS "UIDisabledElements_Rejuv" 65535 "DWord"
Set-Reg $UI  "UIControllableState" 0 "DWord"

# Sticky message in Settings page
$stickyJson = '{"Message":"Device Enrolled Using OfflineInsiderEnroll","LinkTitle":"","LinkUrl":"","DynamicXaml":"<StackPanel xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><TextBlock Style=\"{StaticResource BodyTextBlockStyle }\">This device has been enrolled to the Windows Insider program using OfflineInsiderEnroll. If you want to change settings of the enrollment or stop receiving Windows Insider builds, please use the script.</TextBlock></StackPanel>","Severity":0}'
Set-Reg "$UI\Strings" "StickyMessage" $stickyJson "String"

# --- Step 8: Services and flight signing --------------------------------
Write-Host "[8/8] Starting required services and enabling flight signing..." -ForegroundColor Yellow
$svcs = @(
    @{Name="DiagTrack"; Startup="Automatic"; Action="Start"},
    @{Name="wisvc";     Startup="Manual";    Action="Start"},
    @{Name="wuauserv";  Startup="Manual";    Action="Start"},
    @{Name="UsoSvc";    Startup="Automatic"; Action="Start"}
)
foreach ($svc in $svcs) {
    try {
        Set-Service -Name $svc.Name -StartupType $svc.Startup -ErrorAction Stop
        if ($svc.Action -eq "Start") { Start-Service -Name $svc.Name -ErrorAction Stop }
        Write-Host "  SVC  $($svc.Name) -> $($svc.Startup) [Running]" -ForegroundColor Green
    } catch {
        Write-Host "  WRN  $($svc.Name): $_" -ForegroundColor Yellow
    }
}
try {
    bcdedit /set flightsigning on 2>&1 | Out-Null
    Write-Host "  SET  flightsigning = on" -ForegroundColor Green
} catch {
    Write-Host "  WRN  bcdedit flightsigning failed: $_" -ForegroundColor Yellow
}

# --- System Setup Bypass for older/unsupported machines -----------------
Write-Host "[*] Adding compatibility bypasses for unsupported hardware..." -ForegroundColor Yellow
Set-Reg "HKLM:\SYSTEM\Setup\WindowsUpdate" "AllowWindowsUpdate" 1 "DWord"
Set-Reg "HKLM:\SYSTEM\Setup\MoSetup" "AllowUpgradesWithUnsupportedTPMOrCPU" 1 "DWord"
Set-Reg "HKLM:\SYSTEM\Setup\LabConfig" "BypassRAMCheck" 1 "DWord"
Set-Reg "HKLM:\SYSTEM\Setup\LabConfig" "BypassSecureBootCheck" 1 "DWord"
Set-Reg "HKLM:\SYSTEM\Setup\LabConfig" "BypassStorageCheck" 1 "DWord"
Set-Reg "HKLM:\SYSTEM\Setup\LabConfig" "BypassTPMCheck" 1 "DWord"
Set-Reg "HKCU:\SOFTWARE\Microsoft\PCHC" "UpgradeEligibility" 1 "DWord"

# --- Step 9: FlightingEnabled + BranchReadinessLevel (CRITICAL for WU to fetch flight builds) ---
$branchLevelMap = @{ "1"=$null; "2"=2; "3"=4; "4"=8 }  # Canary=null, Dev=2, Beta=4, ReleasePreview=8
$brl = $branchLevelMap[$choice]
Write-Host "[9/9] Setting FlightingEnabled and BranchReadinessLevel..." -ForegroundColor Yellow
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" "FlightingEnabled" 1 "DWord"
if ($null -ne $brl) {
    Set-Reg $WU "BranchReadinessLevel" $brl "DWord"
} else {
    Remove-ItemProperty -Path $WU -Name "BranchReadinessLevel" -Force -ErrorAction SilentlyContinue
    Write-Host "  CLR  BranchReadinessLevel (Not used in Canary)" -ForegroundColor DarkGray
}

# --- Step 9: Flush WU cache and trigger fresh flight scan ---------------
Write-Host "[9/9] Flushing WU cache and triggering Insider flight scan..." -ForegroundColor Yellow
try {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Stop-Service UsoSvc   -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Remove-Item "C:\Windows\SoftwareDistribution\DataStore\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Start-Service UsoSvc   -ErrorAction SilentlyContinue
    Write-Host "  CLR  WU DataStore cache cleared" -ForegroundColor Green
    Start-Sleep -Seconds 2
    UsoClient StartScan 2>&1 | Out-Null
    wuauclt.exe /detectnow 2>&1 | Out-Null
    Write-Host "  RUN  Windows Update flight scan triggered" -ForegroundColor Green
} catch {
    Write-Host "  WRN  WU cache flush partial: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  SUCCESS: Enrolled in $($cfg.Branch) channel!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT - Next Steps:" -ForegroundColor Yellow
Write-Host "  1. REBOOT YOUR PC (mandatory for flight signing + wisvc)" -ForegroundColor White
Write-Host "  2. After reboot: Settings > Windows Update > Check for Updates" -ForegroundColor White
Write-Host "  3. Insider Preview builds will appear as regular updates" -ForegroundColor White
Write-Host "  4. The Windows Insider Settings page may stay blank on" -ForegroundColor DarkGray
Write-Host "     AtlasOS (the page files were removed). This is normal." -ForegroundColor DarkGray
Write-Host "  5. Your system IS enrolled - updates will still download." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor DarkGray
[void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
