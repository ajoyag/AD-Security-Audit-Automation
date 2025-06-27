# Load required modules
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module BitLocker -ErrorAction SilentlyContinue

# Define helper functions

function Get-WindowsRelease {
    try {
        $props = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

        if ($props.DisplayVersion -and $props.DisplayVersion.Trim() -ne "") {
            return $props.DisplayVersion.Trim()
        }

        if ($props.ReleaseId -and $props.ReleaseId.Trim() -ne "") {
            return $props.ReleaseId.Trim()
        }

        if ($props.CurrentBuild -and $props.UBR -ne $null) {
            return "Build $($props.CurrentBuild).$($props.UBR)"
        }

        $os = Get-CimInstance Win32_OperatingSystem
        if ($os.Caption) {
            return $os.Caption
        }

        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}

function Get-BitLockerEncryptionStatus {
    $fixedDrives = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    $notEncryptedDrives = @()

    foreach ($drive in $fixedDrives) {
        try {
            $bitLocker = Get-BitLockerVolume -MountPoint $drive.DeviceID -ErrorAction Stop
            if ($bitLocker.ProtectionStatus -ne 1) {
                $notEncryptedDrives += $drive.DeviceID.TrimEnd(":")
            }
        }
        catch {
            $notEncryptedDrives += $drive.DeviceID.TrimEnd(":")
        }
    }

    if ($notEncryptedDrives.Count -eq 0) {
        return "YES"
    }
    else {
        return ($notEncryptedDrives -join ",") + " not encrypted"
    }
}

# --- Main script starts here ---

$appToCheck = @("CrowdStrike", "Netskope")

$os = Get-CimInstance Win32_OperatingSystem
$hostname = $env:COMPUTERNAME
$osVersion = $os.Caption
$patches = Get-HotFix | Sort-Object InstalledOn -Descending
$lastWindowsUpdate = $patches | Select-Object -First 1
$lastPatchDate = $lastWindowsUpdate.InstalledOn
$encryptionStatus = Get-BitLockerEncryptionStatus
$winReleaseId = Get-WindowsRelease

$appList = @()
$appList += Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Select-Object DisplayName, InstallDate, DisplayVersion
$appList += Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Select-Object DisplayName, InstallDate, DisplayVersion

# Get local users
$netUsersRaw = net user | Select-Object -Skip 4
$netUsersRaw = $netUsersRaw[0..($netUsersRaw.Count - 3)]

$localUsers = @()
foreach ($line in $netUsersRaw) {
    $localUsers += $line -split '\s+' | Where-Object { $_ -and $_ -notmatch '^(Administrator|Guest|DefaultAccount|WDAGUtilityAccount|krbtgt)$' }
}
$localUsers = $localUsers | Sort-Object -Unique

# Get Active Directory users with required properties only
$adUsers = Get-ADUser -Filter {Enabled -eq $true} -Properties Name, SamAccountName, DistinguishedName

# Build hashtable for AD users keyed by username (SamAccountName)
$adUsersHash = @{}
foreach ($adUser in $adUsers) {
    $adUsersHash[$adUser.SamAccountName.ToLower()] = $adUser
}

$outputCollection = @()
$counter = 1

foreach ($username in $localUsers) {
    $appsFound = @{}

    foreach ($appName in $appToCheck) {
        $foundApps = $appList | Where-Object { $_.DisplayName -like "*$appName*" }

        if ($foundApps) {
            $installDates = @()
            $versions = @()

            foreach ($app in $foundApps) {
                $rawDate = $app.InstallDate
                if ($rawDate) {
                    if ($rawDate -match '^\d{8}$') {
                        try {
                            $dt = [datetime]::ParseExact($rawDate, 'yyyyMMdd', $null)
                            $installDates += $dt
                        } catch {}
                    } else {
                        try {
                            $dt = [datetime]$rawDate
                            $installDates += $dt
                        } catch {}
                    }
                }

                if ($app.DisplayVersion) {
                    $versions += $app.DisplayVersion
                }
            }

            $installDate = if ($installDates.Count -gt 0) { ($installDates | Sort-Object)[0].ToString("yyyy-MM-dd") } else { "N/A" }
            $version = if ($versions.Count -gt 0) { ($versions | Sort-Object)[-1] } else { "N/A" }

            $appsFound[$appName] = @{
                Status = "Installed"
                Date   = $installDate
                Ver    = $version
            }
        }
        else {
            $appsFound[$appName] = @{
                Status = "Not Installed"
                Date   = "N/A"
                Ver    = "N/A"
            }
        }
    }

    # Get AD user info
    $adUserInfo = $null
    $usernameLower = $username.ToLower()
    if ($adUsersHash.ContainsKey($usernameLower)) {
        $adUserInfo = $adUsersHash[$usernameLower]
    }

    # Extract OU formatted as local -> thm -> THM -> Research and Development
    $ou = "N/A"
    if ($adUserInfo) {
        $dn = $adUserInfo.DistinguishedName
        $ouPart = ($dn -replace '^CN=[^,]+,', '')
        $components = $ouPart -split ','
        [array]::Reverse($components)
        $cleanedComponents = $components | ForEach-Object { ($_ -replace '^(OU|DC)=', '') }
        $ou = $cleanedComponents -join ' -> '
    }

    $output = [PSCustomObject]@{
        "S.No"                 = $counter
        "Hostname"             = $hostname
        "User"                 = $username
        "AD_Name"              = if ($adUserInfo) { $adUserInfo.Name } else { "N/A" }
        "AD_OU"                = $ou
        "CrowdStrike"          = $appsFound["CrowdStrike"].Status
        "CrowdStrike Date"     = $appsFound["CrowdStrike"].Date
        "CrowdStrike Version"  = $appsFound["CrowdStrike"].Ver
        "Netskope"             = $appsFound["Netskope"].Status
        "Netskope Date"        = $appsFound["Netskope"].Date
        "Netskope Version"     = $appsFound["Netskope"].Ver
        "Encryption"           = $encryptionStatus
        "Patch"                = $lastPatchDate.ToString("yyyy-MM-dd")
        "Winver"               = $osVersion
        "WinBid"               = $winReleaseId
    }

    $outputCollection += $output
    $counter++
}

# Export results to CSV and show table
$outputCollection | Export-Csv -Path ".\multiuser_laptop_audit_withAD.csv" -NoTypeInformation -Encoding UTF8
$outputCollection | Format-Table -AutoSize

Write-Host "? Audit with AD user info and OU complete! Results saved to 'multiuser_laptop_audit_withAD.csv'."