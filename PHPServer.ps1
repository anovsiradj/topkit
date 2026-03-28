<#
version: 20260328
author : anovsiradj
source : https://copilot.microsoft.com/shares/CiDmc9pCLBUXWv6QLjVdD

.SYNOPSIS
    Launch PHP built-in server with customizable host, port, PHP executable path, and extra arguments.

.DESCRIPTION
    Defaults:
      webHost = 127.0.0.1
      webPort = 5001
      phpPath = "php" (assumes it's in PATH)
      phpArgs = "" (no extra arguments)
    If no arguments are provided, these defaults are used.
    Extra arguments can be passed for document root (-t), custom ini (-c), etc.
#>

param(
    [string]$webHost = "127.0.0.1",
    [int]$webPort = 5001,
    [string]$phpPath = "php",
    [string]$phpArgs = ""
)

# Show effective values
Write-Host "Starting PHP server..."
Write-Host "Host: $webHost"
Write-Host "Port: $webPort"
Write-Host "PHP Executable: $phpPath"
if ($phpArgs -ne "") {
    Write-Host "Extra arguments: $phpArgs"
} else {
    Write-Host "No extra arguments provided."
}

# Run PHP server as external process
& $phpPath -S "${webHost}`:${webPort}" $phpArgs
