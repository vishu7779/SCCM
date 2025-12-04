<# 
SCCM CI – Detect WHfB PIN for active console user (Windows 10/11)
Compliant => Active console user's PIN available (LogonCredsAvailable = 1)
NonCompliant => Otherwise
#>

# region helpers
function Get-ActiveConsoleUserName {
    # Prefer query user / quser (64-bit path)
    $paths = @(
        (Join-Path $env:WINDIR 'System32\query.exe'),
        (Join-Path $env:WINDIR 'System32\quser.exe')
    )
    $raw = $null
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $raw = & $p user 2>$null
            if ([string]::IsNullOrWhiteSpace($raw)) { $raw = & $p 2>$null }
            if ($raw) { break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    # Normalize lines and parse; tolerate leading '>' and variable spacing; be case-insensitive on "console" and "Active"
    $lines = $raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
    foreach ($line in $lines) {
        $norm = ($line -replace '^\>', '') -replace '\s{2,}', '|'
        $parts = $norm.Split('|')
        if ($parts.Count -ge 4) {
            $user   = ($parts[0]).Trim()
            $sess   = ($parts[1]).Trim()
            $state  = ($parts[3]).Trim()
            if ($user -and $sess -and $state) {
                if ($sess -match '^(?i)console$' -and $state -match '^(?i)active$') {
                    return $user
                }
            }
        }
    }
    return $null
}

function Try-TranslateToSid([string]$userName) {
    try {
        if ([string]::IsNullOrWhiteSpace($userName)) { return $null }
        $nt = if ($userName -match '\\') {
            New-Object System.Security.Principal.NTAccount($userName)
        } else {
            New-Object System.Security.Principal.NTAccount("$env:COMPUTERNAME\$userName")
        }
        return $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch { return $null }
}

function Get-InteractiveUserSids {
    # Interactive sessions (LogonType=2) → accounts → SIDs
    try {
        $logon = Get-CimInstance Win32_LogonSession -Filter "LogonType = 2"
        if (-not $logon) { return @() }
        $links = foreach ($ls in $logon) { Get-CimAssociatedInstance -InputObject $ls -ResultClassName Win32_LoggedOnUser }
        $accts = foreach ($ln in $links) { Get-CimAssociatedInstance -InputObject $ln -ResultClassName Win32_Account }
        $sids  = @()
        foreach ($a in ($accts | Where-Object { $_ } | Sort-Object -Property __RELPATH -Unique)) {
            $name = if ($a.Domain) { "$($a.Domain)\$($a.Name)" } else { $a.Name }
            $sid = Try-TranslateToSid $name
            if ($sid) { $sids += $sid }
        }
        return $sids | Select-Object -Unique
    } catch { return @() }
}

function Get-LoadedUserHivesSids {
    # HKEY_USERS contains loaded user hives (ignore machine SIDs)
    $result = @()
    try {
        $hku = 'Registry::HKEY_USERS'
        Get-ChildItem $hku -ErrorAction Stop | ForEach-Object {
            $sid = $_.PSChildName
            if ($sid -match '^S-1-5-21-\d+-\d+-\d+-\d+$') { $result += $sid }
        }
    } catch {}
    return $result | Select-Object -Unique
}
# endregion

# region main
try {
    $pinProviderGuid = '{D6886603-9D2F-4EB2-B667-1971041FA96B}'
    $baseKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\$pinProviderGuid"

    if (-not (Test-Path $baseKey)) { 'NonCompliant'; return }

    # 1) Active console user → SID
    $activeUser = Get-ActiveConsoleUserName
    $targetSids = @()
    if ($activeUser) {
        $sid = Try-TranslateToSid $activeUser
        if ($sid) { $targetSids += $sid }
    }

    # 2) Fallback: any interactive user SIDs
    if (-not $targetSids) {
        $targetSids += Get-InteractiveUserSids
    }

    # 3) Fallback: any loaded user hive SIDs
    if (-not $targetSids) {
        $targetSids += Get-LoadedUserHivesSids
    }

    $targetSids = $targetSids | Select-Object -Unique
    if (-not $targetSids) { 'NonCompliant'; return }

    foreach ($sid in $targetSids) {
        $perSidKey = Join-Path $baseKey $sid
        if (Test-Path $perSidKey) {
            try {
                $val = (Get-ItemProperty -Path $perSidKey -ErrorAction Stop).LogonCredsAvailable
                if ($val -eq 1) { 'Compliant'; return }
            } catch {}
        }
    }

    'NonCompliant'
}
catch {
    'NonCompliant'
}
# endregion
