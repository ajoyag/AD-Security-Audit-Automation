# ==========================================================
# Single Laptop Audit
# ==========================================================

# CONFIG
$appToCheck = @("Google Chrome", "Mozilla Firefox", "Microsoft Office", "CrowdStrike", "Netskope")

# SYSTEM INFO
$os = Get-CimInstance Win32_OperatingSystem
$hostname = $env:COMPUTERNAME
$osVersion = $os.Caption
$osBuild = $os.BuildNumber

# PATCH INFO
$patches = Get-HotFix | Select-Object HotFixID, InstalledOn
$lastWindowsUpdate = ($patches | Sort-Object InstalledOn -Descending | Select-Object -First 1)

# BITLOCKER STATUS (Check C: drive)
$bitLockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
$encryptionStatus = if ($bitLockerStatus.ProtectionStatus -eq 1) { "Encrypted" } else { "Not Encrypted" }

# INSTALLED APPLICATIONS
$appList = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Select-Object DisplayName, DisplayVersion

$appList += Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Select-Object DisplayName, DisplayVersion

# CHROME VERSION FALLBACK
$chromePaths = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
)
foreach ($chromePath in $chromePaths) {
    if (Test-Path $chromePath) {
        $appList += [PSCustomObject]@{
            DisplayName     = "Google Chrome"
            DisplayVersion  = (Get-Item $chromePath).VersionInfo.ProductVersion
        }
        break
    }
}

# APP INSTALLATION CHECK
$appsFound = @{}
foreach ($appName in $appToCheck) {
    $match = $appList | Where-Object { $_.DisplayName -and $_.DisplayName -like "*$appName*" } | Select-Object -First 1
    if ($match) {
        $appsFound[$appName] = "Installed"
    } else {
        $appsFound[$appName] = "Not Installed"
    }
}

# OtherApps Summary
$otherApps = @()
foreach ($key in $appToCheck[0..2]) {  # Only Chrome, Firefox, Office
    $status = $appsFound[$key]
    $otherApps += "$key: $status"
}
$otherAppsSummary = $otherApps -join ", "

# FINAL OUTPUT FORMATTED AS REQUIRED
$output = [PSCustomObject]@{
    'S.No'        = 1
    'Hostname'    = $hostname
    'Location'    = ""  # Optional - fill manually or dynamically if needed
    'CrowdStrike' = $appsFound["CrowdStrike"]
    'Netskope'    = $appsFound["Netskope"]
    'Encryption'  = $encryptionStatus
    'Patch'       = $lastWindowsUpdate.InstalledOn.ToString("yyyy-MM-dd")
    'Winver'      = $osVersion
    'WinBid'      = $osBuild
    'OtherApps'   = $otherAppsSummary
    'Remarks'     = ""  # Optional - you can set logic or fill manually
}

# Export CSV
$output | Export-Csv -Path ".\single_laptop_audit.csv" -NoTypeInformation -Encoding UTF8
$output | Format-Table -AutoSize

Write-Host "✅ Done! Results saved to 'single_laptop_audit.csv'."
