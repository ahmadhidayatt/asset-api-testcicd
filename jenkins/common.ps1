##############################################################################
# common.ps1
# PowerShell port of common.lib for Jenkins Windows
##############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve directories
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT_DIR   = Resolve-Path "$SCRIPT_DIR\.."

##############################################################################
# Ping API Gateway Server
# Usage: Ping-ApigatewayServer <SERVER_URL> <PAUSE> <ITERATIONS>
##############################################################################
function Ping-ApigatewayServer {
    param (
        [string]$Server,
        [int]$Pause,
        [int]$Iterations
    )

    $healthUrl = "$Server/rest/apigateway/health"

    while ($true) {
        if ($Iterations -eq 0) { return 0 }

        try {
            Invoke-WebRequest -Uri $healthUrl -UseBasicParsing | Out-Null
            return 1
        } catch {
            Write-Host "$Server is down"
            $Iterations--
            Start-Sleep -Seconds $Pause
        }
    }
}

##############################################################################
# Import API
# Usage: Import-Api <api_project> <url> <username> <password>
##############################################################################
function Import-Api {
    param (
        [string]$ApiProject,
        [string]$Url,
        [string]$Username,
        [string]$Password
    )

    $apiDir = Join-Path $ROOT_DIR "apis\$ApiProject"
    $zipFile = Join-Path $ROOT_DIR "$ApiProject.zip"

    if (!(Test-Path $apiDir)) {
        throw "API folder not found: $apiDir"
    }

    if (Test-Path $zipFile) { Remove-Item $zipFile -Force }

    Compress-Archive -Path "$apiDir\*" -DestinationPath $zipFile

    $bytes = [System.IO.File]::ReadAllBytes($zipFile)
    $auth  = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$Username`:$Password")
    )

    Invoke-RestMethod `
        -Uri "$Url/rest/apigateway/archive?overwrite=*" `
        -Method Post `
        -Headers @{
            Authorization = "Basic $auth"
            Accept = "application/json"
        } `
        -ContentType "application/zip" `
        -Body $bytes | Out-Null

    Remove-Item $zipFile -Force
    Write-Host "Import API OK: $ApiProject"
}

##############################################################################
# Export API
# Usage: Export-Api <api_project> <url> <username> <password>
##############################################################################
function Export-Api {
    param (
        [string]$ApiProject,
        [string]$Url,
        [string]$Username,
        [string]$Password
    )

    $apiDir = Join-Path $ROOT_DIR "apis\$ApiProject"
    $zipFile = Join-Path $ROOT_DIR "$ApiProject.zip"

    if (!(Test-Path $apiDir)) {
        throw "API directory not found: $apiDir"
    }

    $auth = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$Username`:$Password")
    )

    Invoke-WebRequest `
        -Uri "$Url/rest/apigateway/archive" `
        -Method Post `
        -Headers @{
            Authorization = "Basic $auth"
            "x-HTTP-Method-Override" = "GET"
        } `
        -ContentType "application/json" `
        -InFile "$apiDir\export_payload.json" `
        -OutFile $zipFile

    Expand-Archive -Path $zipFile -DestinationPath $apiDir -Force
    Remove-Item $zipFile -Force

    Write-Host "Export API OK: $ApiProject"
}

##############################################################################
# Import Configurations
##############################################################################
function Import-Configurations {
    param (
        [string]$ConfigName,
        [string]$Url,
        [string]$Username,
        [string]$Password
    )

    $confDir = Join-Path (Get-Location) $ConfigName
    if (!(Test-Path $confDir)) {
        throw "Configuration not found: $ConfigName"
    }

    $zipFile = Join-Path $confDir "config.zip"
    Compress-Archive -Path "$confDir\*" -DestinationPath $zipFile -Force

    $auth  = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$Username`:$Password")
    )
    $bytes = [System.IO.File]::ReadAllBytes($zipFile)

    Invoke-RestMethod `
        -Uri "$Url/rest/apigateway/archive?overwrite=*" `
        -Method Post `
        -Headers @{
            Authorization = "Basic $auth"
            Accept = "application/json"
        } `
        -ContentType "application/zip" `
        -Body $bytes | Out-Null

    Remove-Item $zipFile -Force
    Write-Host "Import configuration OK: $ConfigName"
}

##############################################################################
# Split helper
##############################################################################
function Split-String {
    param (
        [string]$Input,
        [string]$Delimiter
    )
    return $Input -split [Regex]::Escape($Delimiter)
}
