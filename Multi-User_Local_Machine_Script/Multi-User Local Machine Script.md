# Objective
Perform an audit on a Windows laptop focusing on all local user accounts to gather:

- Windows OS version and build information.
- BitLocker encryption status of fixed drives.
- Latest installed Windows updates.
- Installation status, version, and install date of specific security applications (e.g., CrowdStrike, Netskope) per user.
- Export detailed per-user audit results to a .csv for review.

---

## Features

✅ Retrieves:

- Windows OS Version and Release Build.
- BitLocker encryption status on fixed drives.
- List of local users (excluding built-in system accounts).
- Installed applications (CrowdStrike, Netskope) with version and install date per user.
- Date of the most recent Windows Update.
- Exports audit results to a .csv file.

---

## Script

```powershell
# ==========================================================

# Multi-User Laptop Audit - Final Code

# ==========================================================

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

$netUsersRaw = net user | Select-Object -Skip 4

$netUsersRaw = $netUsersRaw[0..($netUsersRaw.Count - 3)]

$users = @()

foreach ($line in $netUsersRaw) {

    $users += $line -split '\s+' | Where-Object { $_ -and $_ -notmatch '^(Administrator|Guest|DefaultAccount|WDAGUtilityAccount|krbtgt)$' }

}

$users = $users | Sort-Object -Unique

$outputCollection = @()

$counter = 1

foreach ($username in $users) {

    $appsFound = @{}

    foreach ($appName in $appToCheck) {

        $foundApps = $appList | Where-Object { $_.DisplayName -like "*$appName*" }

        if ($foundApps) {

            $installDates = @()

            $versions = @()

            foreach ($app in $foundApps) {

                # Process install date

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

                # Process version

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

    $output = [PSCustomObject]@{

        "S.No"                 = $counter

        "Hostname"             = $hostname

        "User"                 = $username

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

# Export to CSV

$outputCollection | Export-Csv -Path ".\multiuser_laptop_audit.csv" -NoTypeInformation -Encoding UTF8

$outputCollection | Format-Table -AutoSize

Write-Host "✅ Audit complete! Results saved to 'multiuser_laptop_audit.csv'."
```

---

## Output

The script generates a `multiuser_laptop_audit.csv` file containing:

|Field|Description|
|---|---|
|S.No|Serial number (row count)|
|Hostname|Machine hostname|
|User|Local username|
|CrowdStrike|Installation status of CrowdStrike|
|CrowdStrike Date|Installation date of CrowdStrike|
|CrowdStrike Version|Installed CrowdStrike version|
|Netskope|Installation status of Netskope|
|Netskope Date|Installation date of Netskope|
|Netskope Version|Installed Netskope version|
|Encryption|BitLocker encryption status (YES or drives not encrypted)|
|Patch|Date of the most recent Windows update|
|Winver|Windows OS version|
|WinBid|Windows build number and UBR|

---

## Usage Instructions

1. Save the script as `multiuser_laptop_audit.ps1`.
    
2. Open **PowerShell as Administrator**.
    
3. Run the script:
    

```powershell
.\multiuser_laptop_audit.ps1
```

4. Results will be saved to:
    

```
.\multiuser_laptop_audit.csv
```

5. Confirm execution by viewing the formatted table printed to your PowerShell window.
    

---

## Summary

This script is designed to perform a detailed audit on Windows laptops with multiple local user accounts, collecting user-specific installation information on critical security applications, encryption status, and system patch data. It is useful for enterprise compliance, security posture reviews, and detailed asset inventory gathering across multi-user endpoints.