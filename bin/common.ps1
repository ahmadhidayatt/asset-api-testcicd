##############################################################################
# common.ps1
# PowerShell port of common.lib for Jenkins Windows (FINAL)
##############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve directories
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT_DIR   = Resolve-Path "$SCRIPT_DIR\.."

##############################################################################
# Ping API Gateway Server
##############################################################################
function Ping-ApigatewayServer {
    param (
        [Parameter(Mandatory)]
        [Alias('GatewayUrl')]
        [string]$Server,

        [int]$Pause,
        [int]$Iterations
    )

    $BaseUrl   = $Server.Trim().TrimEnd('/')
    $HealthUri = "$BaseUrl/rest/apigateway/health"

    while ($true) {
        if ($Iterations -eq 0) { return 0 }

        try {
            Invoke-WebRequest -Uri ([System.Uri]$HealthUri) -UseBasicParsing | Out-Null
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
##############################################################################
function Import-Api {
    param (
        [Parameter(Mandatory)]
        [string]$ApiProject,

        [Parameter(Mandatory)]
        [Alias('GatewayUrl')]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        throw "APIGATEWAY_URL is empty"
    }

    $ApiDir  = Join-Path $ROOT_DIR "apis\$ApiProject"
    $ZipFile = Join-Path $ROOT_DIR "$ApiProject.zip"

    if (!(Test-Path $ApiDir)) {
        throw "API folder not found: $ApiDir"
    }

    if (Test-Path $ZipFile) {
        Remove-Item $ZipFile -Force
    }

    Compress-Archive -Path "$ApiDir\*" -DestinationPath $ZipFile -Force

    $Bytes = [System.IO.File]::ReadAllBytes($ZipFile)
    $Auth  = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$Username`:$Password")
    )

    $BaseUrl    = $Url.Trim().TrimEnd('/')
    $RequestUri = "$BaseUrl/rest/apigateway/archive?overwrite=*"

    Write-Host "DEBUG RequestUri=[$RequestUri]"

    $ParsedUri = [System.Uri]$RequestUri

    Invoke-RestMethod `
        -Uri $ParsedUri `
        -Method Post `
        -Headers @{
            Authorization = "Basic $Auth"
            Accept        = "application/json"
        } `
        -ContentType "application/zip" `
        -Body $Bytes | Out-Null

    Remove-Item $ZipFile -Force
    Write-Host "Import API OK: $ApiProject"
}

##############################################################################
# Export API
##############################################################################
function Export-Api {
    param (
        [Parameter(Mandatory)]
        [string]$ApiProject,

        [Parameter(Mandatory)]
        [Alias('GatewayUrl')]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

    $ApiDir  = Join-Path $ROOT_DIR "apis\$ApiProject"
    $ZipFile = Join-Path $ROOT_DIR "$ApiProject.zip"

    if (!(Test-Path $ApiDir)) {
        throw "API directory not found: $ApiDir"
    }

    $Auth = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$Username`:$Password")
    )

    $BaseUrl    = $Url.Trim().TrimEnd('/')
    $RequestUri = "$BaseUrl/rest/apigateway/archive"

    Invoke-WebRequest `
        -Uri ([System.Uri]$RequestUri) `
        -Method Post `
        -Headers @{
            Authorization            = "Basic $Auth"
            "x-HTTP-Method-Override" = "GET"
        } `
        -ContentType "application/json" `
        -InFile "$ApiDir\export_payload.json" `
        -OutFile $ZipFile

    Expand-Archive -Path $ZipFile -DestinationPath $ApiDir -Force
    Remove-Item $ZipFile -Force

    Write-Host "Export API OK: $ApiProject"
}

##############################################################################
# Import Configurations
##############################################################################
function Import-Configurations {
    param (
        [Parameter(Mandatory)]
        [string]$ConfigName,

        [Parameter(Mandatory)]
        [Alias('GatewayUrl')]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

    $ConfDir = Join-Path (Get-Location) $ConfigName
    if (!(Test-Path $ConfDir)) {
        throw "Configuration not found: $ConfigName"
    }

    $ZipFile = Join-Path $ConfDir "config.zip"
    Compress-Archive -Path "$ConfDir\*" -DestinationPath $ZipFile -Force

    $Auth  = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$Username`:$Password")
    )
    $Bytes = [System.IO.File]::ReadAllBytes($ZipFile)

    $BaseUrl    = $Url.Trim().TrimEnd('/')
    $RequestUri = "$BaseUrl/rest/apigateway/archive?overwrite=*"

    Invoke-RestMethod `
        -Uri ([System.Uri]$RequestUri) `
        -Method Post `
        -Headers @{
            Authorization = "Basic $Auth"
            Accept        = "application/json"
        } `
        -ContentType "application/zip" `
        -Body $Bytes | Out-Null

    Remove-Item $ZipFile -Force
    Write-Host "Import configuration OK: $ConfigName"
}

##############################################################################
# Split helper
##############################################################################
function Split-String {
    param (
        [Parameter(Mandatory)]
        [string]$Input,

        [Parameter(Mandatory)]
        [string]$Delimiter
    )

    return $Input.Split($Delimiter)
}

