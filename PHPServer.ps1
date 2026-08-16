<#
.SYNOPSIS
  Start PHP built-in server with customizable host, port, phpPath and phpArgs.

USAGE
  See examples below for how to pass phpArgs safely.
  - `C:\topkit\PHPServer.ps1 -phpArgs @('-t', '.\.agents\')`
  - `C:\topkit\PHPServer.ps1 -phpArgs '-t', '.\.agents\'`
#>

param(
    [string]$webHost = "127.0.0.1",
    [int]$webPort = 5001,
    [string]$phpPath = "php",
    [string[]]$phpArgs = @()
)

Write-Host "Starting PHP server..."
Write-Host "Host: $webHost"
Write-Host "Port: $webPort"
Write-Host "PHP Executable: $phpPath"
if ($phpArgs.Count -gt 0) { Write-Host "phpArgs: $($phpArgs -join ' ')" } else { Write-Host "No extra phpArgs provided." }

# If phpPath is a file path, ensure it exists
if ($phpPath -ne "php" -and -not (Test-Path $phpPath)) {
    Write-Error "PHP executable not found at: $phpPath"
    exit 1
}

# Build argument array and run
$arguments = @("-S", "$webHost`:$webPort") + $phpArgs
Write-Host "Running: $phpPath $($arguments -join ' ')"
& $phpPath @arguments
