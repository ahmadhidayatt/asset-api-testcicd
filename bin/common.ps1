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
# Helper: Build Basic Auth Header
##############################################################################
function New-BasicAuthHeader {
    param (
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

    $token = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$Username`:$Password")
    )

    return @{
        Authorization = "Basic $token"
    }
}
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
    $RequestUri = "$BaseUrl/rest/apigatewayui/apigateway/archive?overwrite=apis,policies,policyactions&fixingMissingVersions=false"

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

function Resolve-ApiId {
    param (
        [string]$ApiName,
        [string]$Url,
        [string]$Username,
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($ApiName)) {
        throw "ApiName is empty"
    }

    $BaseUrl = $Url.Trim().TrimEnd('/')
    $SearchUri = "$BaseUrl/rest/apigateway/search"

    $Headers = New-BasicAuthHeader -Username $Username -Password $Password
    $Headers["Content-Type"] = "application/json"

    $Payload = @{
        types     = @("api")
        condition = "and"
        scope     = @(
            @{
                attributeName = "apiName"
                keyword       = $ApiName
            }
        )
    } | ConvertTo-Json -Depth 6

    Write-Host "DEBUG Searching API ID for [$ApiName]"

    $Resp = Invoke-RestMethod `
        -Uri $SearchUri `
        -Method Post `
        -Headers $Headers `
        -Body $Payload

    if (-not $Resp.api -or $Resp.api.Count -eq 0) {
        throw "API NOT FOUND in Gateway: $ApiName"
    }

    if ($Resp.api.Count -gt 1) {
        Write-Warning "Multiple APIs found for name [$ApiName], using first result"
    }

    $ApiId = $Resp.api[0].id
    Write-Host "DEBUG Resolved API ID: $ApiId"

    return $ApiId
}

##############################################################################
# EXPORT API (MAIN FUNCTION)
##############################################################################
function Export-Api {
    param (
        [Parameter(Mandatory)]
        [string]$ApiProject,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

    Write-Host "=== EXPORT API START ==="
    Write-Host "API NAME : $ApiProject"
    Write-Host "GATEWAY  : $Url"

    $BaseUrl = $Url.Trim().TrimEnd('/')

    # Resolve API ID
    $ApiId = Resolve-ApiId `
        -ApiName $ApiProject `
        -Url $BaseUrl `
        -Username $Username `
        -Password $Password

    # Prepare paths
    $ApiDir  = Join-Path $ROOT_DIR "apis\$ApiProject"
    $ZipFile = Join-Path $ROOT_DIR "$ApiProject.zip"

    if (Test-Path $ApiDir) {
        Remove-Item $ApiDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ApiDir | Out-Null

    $Headers = New-BasicAuthHeader -Username $Username -Password $Password
    $Headers["Accept"] = "application/octet-stream"

    # EXPORT FULL API (safe defaults)
    $RequestUri = "$BaseUrl/rest/apigateway/archive" +
                  "?apis=$ApiId" +
                  "&include-registered-applications=true" +
                  "&include-users=true" +
                  "&include-groups=true"

    Write-Host "DEBUG Export URI:"
    Write-Host $RequestUri

    Invoke-WebRequest `
        -Uri ([System.Uri]$RequestUri) `
        -Method Get `
        -Headers $Headers `
        -OutFile $ZipFile

    if (!(Test-Path $ZipFile)) {
        throw "Export failed: ZIP not created"
    }

    Expand-Archive -Path $ZipFile -DestinationPath $ApiDir -Force
    Remove-Item $ZipFile -Force

    Write-Host "EXPORT API OK: $ApiProject"
    Write-Host "Output dir: $ApiDir"
    Write-Host "=== EXPORT API END ==="
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


if (-not (Test-Path variable:LASTEXITCODE)) {
    $global:LASTEXITCODE = 0
}
