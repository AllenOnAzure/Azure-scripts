# PowerShell - Moves the Windows page file to the temporary disk # 

# ------------ CONFIG ------------
# Replace 'D:' with the drive letter of your temporary disk if different
$driveLetter = 'D:'
# ------------ /CONFIG ------------

# Ensure we are running as Administrator
$currId   = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currId)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Error "Please run PowerShell as Administrator."
    return
}

# Validate target drive
if (-not (Get-PSDrive -Name $driveLetter.TrimEnd(':') -ErrorAction SilentlyContinue)) {
    Write-Error "Drive $driveLetter not found. Open Disk Management to confirm the temp disk letter."
    return
}

# Helper: registry path for memory management
$mmReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'

Write-Host "Disabling global 'Automatically manage paging file size'..." -ForegroundColor Cyan
Set-ItemProperty -Path $mmReg -Name 'AutomaticManagedPagefile' -Value 0 -Type DWord

Write-Host "Removing any existing page file settings..." -ForegroundColor Cyan
# Remove all Win32_PageFileSetting instances so we start clean
Get-WmiObject -Class Win32_PageFileSetting -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $_.Delete() | Out-Null
    } catch {
        Write-Warning "Could not remove existing setting for $($_.Name): $($_.Exception.Message)"
    }
}

# Construct path for the new page file
$pageFilePath = Join-Path $driveLetter 'pagefile.sys'

Write-Host "Creating system-managed page file on $pageFilePath ..." -ForegroundColor Cyan
# According to Win32_PageFileSetting, 0 for InitialSize/MaximumSize lets the system manage the size.
# Using Set-WMIInstance to create a new setting
Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{
    Name        = $pageFilePath
    InitialSize = 0
    MaximumSize = 0
} | Out-Null

# OPTIONAL: if you want kernel dump support, ensure CrashDumpEnabled is set (e.g., 2 = Kernel memory dump)
# Set-ItemProperty -Path $mmReg -Name 'CrashDumpEnabled' -Value 2 -Type DWord

Write-Host "`nCurrent configured PageFileSetting objects:" -ForegroundColor Yellow
Get-WmiObject -Class Win32_PageFileSetting | Select-Object Name, InitialSize, MaximumSize | Format-Table -AutoSize

Write-Host "`nCurrent usage (will fully reflect after reboot):" -ForegroundColor Yellow
Get-WmiObject -Class Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage | Format-Table -AutoSize

Write-Host "`nConfiguration complete. A system restart is required." -ForegroundColor Green
``