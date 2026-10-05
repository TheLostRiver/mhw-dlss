# Shared by the installer and recovery tool; compatible with Windows PowerShell 5.1.
function Set-SectionValue {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$Section,
        [string]$Key,
        [string]$Value,
        [string]$Separator = '='
    )

    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Text.TrimStart([char]0xFEFF) -split '\r?\n')) { $lines.Add($line) }
    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[([^\]]+)\]\s*(?:[#;].*)?$') {
            if ($sectionStart -ge 0) { $sectionEnd = $i; break }
            if ($Matches[1] -eq $Section) { $sectionStart = $i }
        }
    }

    $entry = "$Key$Separator$Value"
    if ($sectionStart -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
        $lines.Add("[$Section]")
        $lines.Add($entry)
    } else {
        $found = $false
        for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
            if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
                $lines[$i] = $entry
                $found = $true
            }
        }
        if (-not $found) { $lines.Insert($sectionEnd, $entry) }
    }
    return (($lines -join $newline).TrimEnd("`r", "`n") + $newline)
}

function Write-GameConfig {
    param([string]$Path, [string]$Text)
    # Set-Content -Encoding UTF8 emits a BOM in Windows PowerShell 5.1.
    # MHW then fails to read [GraphicsOption] and may fall back to DX11.
    [IO.File]::WriteAllText($Path, $Text.TrimStart([char]0xFEFF), [Text.UTF8Encoding]::new($false))
}
