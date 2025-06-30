# Load Active Directory module
Import-Module ActiveDirectory -ErrorAction Stop

# Get list of laptops dynamically (filter for Windows OS machines)
$laptops = Get-ADComputer -Filter 'OperatingSystem -like "*Windows*"' | Select-Object -ExpandProperty Name

# Store audit results
$results = @()
$sno = 1

foreach ($laptop in $laptops) {
    Write-Host "`nAuditing $laptop..." -ForegroundColor Cyan

    try {
        $remoteResult = Invoke-Command -ComputerName $laptop -ScriptBlock {
            function Get-WindowsRelease {
                try {
                    $props = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
                    if ($props.DisplayVersion) { return $props.DisplayVersion.Trim() }
                    if ($props.ReleaseId) { return $props.ReleaseId.Trim() }
                    if ($props.CurrentBuild -and $props.UBR) {
                        return "Build $($props.CurrentBuild).$($props.UBR)"
                    }
                    return (Get-CimInstance Win32_OperatingSystem).Caption
                } catch { return "Unknown" }
            }

            function Get-BitLockerEncryptionStatus {
                $fixedDrives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
                $unencrypted = @()

                foreach ($drive in $fixedDrives) {
                    try {
                        $status = Get-BitLockerVolume -MountPoint $drive.DeviceID
                        if ($status.ProtectionStatus -ne 1) {
                            $unencrypted += $drive.DeviceID.TrimEnd(":")
                        }
                    } catch {
                        $unencrypted += $drive.DeviceID.TrimEnd(":")
                    }
                }

                if ($unencrypted.Count -eq 0) {
                    return "YES"
                } else {
                    return ($unencrypted -join ",") + " not encrypted"
                }
            }

            $hostname = $env:COMPUTERNAME
            $os = Get-CimInstance Win32_OperatingSystem
            $osVersion = $os.Caption
            $winRelease = Get-WindowsRelease
            $lastPatch = (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn
            $bitLockerStatus = Get-BitLockerEncryptionStatus

            # Get local users
            $raw = net user | Select-Object -Skip 4
            $raw = $raw[0..($raw.Count - 3)]
            $users = @()
            foreach ($line in $raw) {
                $users += $line -split '\s+' | Where-Object {
                    $_ -and $_ -notmatch '^(Administrator|Guest|DefaultAccount|WDAGUtilityAccount|krbtgt)$'
                }
            }
            $users = $users | Sort-Object -Unique

            # Get installed applications
            $apps = @()
            $apps += Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
            $apps += Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue

            $appCheck = @("CrowdStrike", "Netskope")
            $audits = @()

            foreach ($user in $users) {
                $entry = [PSCustomObject]@{
                    Hostname              = $hostname
                    User                  = $user
                    OS_Version            = $osVersion
                    WinBuild              = $winRelease
                    LastPatch             = $lastPatch.ToString("yyyy-MM-dd")
                    Encryption            = $bitLockerStatus
                }

                foreach ($app in $appCheck) {
                    $found = $apps | Where-Object { $_.DisplayName -like "*$app*" }
                    if ($found) {
                        $ver = ($found | Select-Object -ExpandProperty DisplayVersion -First 1) -replace '\s+$'
                        $rawDate = ($found | Select-Object -ExpandProperty InstallDate -First 1)
                        if ($rawDate -match '^\d{8}$') {
                            $date = [datetime]::ParseExact($rawDate, 'yyyyMMdd', $null).ToString("yyyy-MM-dd")
                        } else {
                            $date = "N/A"
                        }
                        $entry | Add-Member -NotePropertyName "$app" -NotePropertyValue "Installed"
                        $entry | Add-Member -NotePropertyName "$app Date" -NotePropertyValue $date
                        $entry | Add-Member -NotePropertyName "$app Version" -NotePropertyValue $ver
                    } else {
                        $entry | Add-Member -NotePropertyName "$app" -NotePropertyValue "Not Installed"
                        $entry | Add-Member -NotePropertyName "$app Date" -NotePropertyValue "N/A"
                        $entry | Add-Member -NotePropertyName "$app Version" -NotePropertyValue "N/A"
                    }
                }

                $audits += $entry
            }

            return $audits
        } -ErrorAction Stop

        # AD lookup and enrichment
        foreach ($row in $remoteResult) {
            $usernameOnly = ($row.User -split '\\')[-1]
            $adUser = Get-ADUser -Filter { SamAccountName -eq $usernameOnly } -Properties Name, DistinguishedName
            if ($adUser) {
                $dn = $adUser.DistinguishedName
                $ou = ($dn -replace '^CN=[^,]+,', '') -split ',' | ForEach-Object { $_ -replace '^(OU|DC)=', '' }
                [array]::Reverse($ou)
                $row | Add-Member -NotePropertyName AD_Name -NotePropertyValue $adUser.Name
                $row | Add-Member -NotePropertyName AD_OU -NotePropertyValue ($ou -join ' -> ')
            } else {
                $row | Add-Member -NotePropertyName AD_Name -NotePropertyValue "N/A"
                $row | Add-Member -NotePropertyName AD_OU -NotePropertyValue "N/A"
            }

            # Add S.No for output
            $row | Add-Member -NotePropertyName "S.No" -NotePropertyValue $sno
            $sno++

            # Rename properties to match requested output
            $finalObj = [PSCustomObject]@{
                "S.No"                = $row.'S.No'
                "Hostname"            = $row.Hostname
                "User"                = $row.User
                "AD_Name"             = $row.AD_Name
                "AD_OU"               = $row.AD_OU
                "CrowdStrike"         = $row.CrowdStrike
                "CrowdStrike Date"    = $row.'CrowdStrike Date'
                "CrowdStrike Version" = $row.'CrowdStrike Version'
                "Netskope"            = $row.Netskope
                "Netskope Date"       = $row.'Netskope Date'
                "Netskope Version"    = $row.'Netskope Version'
                "Encryption"          = $row.Encryption
                "Patch"               = $row.LastPatch
                "Winver"              = $row.OS_Version
                "WinBid"              = $row.WinBuild
            }

            $results += $finalObj
        }

    } catch {
        Write-Warning "❌ Failed to audit ${laptop}: $_"
    }
}

# Export results to CSV with only required columns
$results | Select-Object "S.No", "Hostname", "User", "AD_Name", "AD_OU", `
    "CrowdStrike", "CrowdStrike Date", "CrowdStrike Version", `
    "Netskope", "Netskope Date", "Netskope Version", `
    "Encryption", "Patch", "Winver", "WinBid" | `
    Export-Csv -Path ".\DomainLaptopAudit.csv" -NoTypeInformation -Encoding UTF8

Write-Host "`n✅ Audit complete. Output saved to 'DomainLaptopAudit.csv'." -ForegroundColor Green
