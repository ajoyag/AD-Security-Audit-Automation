# ==========================================================
# Final Single Laptop Audit (Compatible Version)
# ==========================================================
# CONFIG
$appsToCheck = @("Google Chrome", "Mozilla Firefox", "Microsoft Office") 

# SYSTEM INFO
$os = Get-CimInstance Win32_OperatingSystem
$hostname = $env:COMPUTERNAME
$osVersion = $os.Caption
$osBuild = $os.BuildNumber
$patches = Get-HotFix | Select-Object HotFixID, InstalledOn
$lastWindowsUpdate = ($patches | Sort-Object InstalledOn -Descending | Select-Object -First 1)

# APPLICATIONS
$appList = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
           Select-Object DisplayName, DisplayVersion
$appList += Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
           Select-Object DisplayName, DisplayVersion

# CHROME FALLBACK
$chromePaths = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
)

foreach ($chromePath in $chromePaths) {
    if (Test-Path $chromePath) {
        $appList += [PSCustomObject]@{
            DisplayName    = "Google Chrome"
            DisplayVersion = (Get-Item $chromePath).VersionInfo.ProductVersion
        }
        break
    }
}

# SELECTED APPLICATIONS
$selectedAppCheckList = @()
foreach ($appName in $appsToCheck) {
    $app = $appList | Where-Object { $_.DisplayName -and $_.DisplayName -like "*$appName*" } | Select-Object -First 1
    if ($app) {
        $selectedAppCheckList += "${appName}: Installed"
    } else {
        $selectedAppCheckList += "${appName}: Not Installed"
    }
}
$selectedAppCheck = $selectedAppCheckList -join ", "

# SELECTED APPLICATIONS VERSIONS
$selectedAppVersionsList = @()
foreach ($appName in $appsToCheck) {
    $app = $appList | Where-Object { $_.DisplayName -and $_.DisplayName -like "*$appName*" } | Select-Object -First 1
    if ($app) {
        $selectedAppVersionsList += "${appName}: $($app.DisplayVersion)"
    } else {
        $selectedAppVersionsList += "${appName}: N/A"
    }
}
$selectedAppVersions = $selectedAppVersionsList -join ", "

# PATCH LIST
$patchListString = ($patches | ForEach-Object {
    "$($_.HotFixID) [$($_.InstalledOn.ToString('dd-MM-yyyy HH:mm'))]"
}) -join ", "

# FINAL OUTPUT
$output = [PSCustomObject]@{
    Hostname            = $hostname
    OSVersion           = $osVersion
    OSBuild             = $osBuild
    SelectedAppCheck    = $selectedAppCheck
    SelectedAppVersions = $selectedAppVersions
    LastWindowsUpdate   = $lastWindowsUpdate.InstalledOn
    PatchList           = $patchListString
}

# Export Results
$output | Export-Csv -Path ".\single_laptop_audit.csv" -NoTypeInformation
$output | Format-Table
Write-Host "✅ Done! Results saved to 'single_laptop_audit.csv'."

Read-Host "Press Enter to exit..."
