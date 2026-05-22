# AzureDevOpsApi.Core.psm1
# Core functions for Azure DevOps REST API operations

<#
.SYNOPSIS
    Invokes an Azure DevOps REST API endpoint.

.DESCRIPTION
    Core function that all other module functions use to call the Azure DevOps REST API.
    Handles authentication (Bearer or Basic), JSON serialization, retry logic with exponential backoff,
    and file downloads via the OutFile parameter.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER ApiPath
    Relative API path appended to https://dev.azure.com/{Organization}/{Project}/_apis/

.PARAMETER Method
    HTTP method: GET (default), POST, PUT, PATCH, or DELETE

.PARAMETER Body
    Request body object; automatically serialized to JSON

.PARAMETER ApiVersion
    API version string (default: "7.0")

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER OutFile
    File path for downloading content instead of returning JSON

.PARAMETER MaxRetries
    Maximum number of retry attempts for transient errors (default: 3)

.PARAMETER RetryDelaySeconds
    Base delay in seconds between retries with exponential backoff (default: 2)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.PARAMETER BaseUrl
    Base URL for the API. Defaults to "https://dev.azure.com".
    Use "https://pkgs.dev.azure.com" for NuGet flat container API.

.EXAMPLE
    $response = Invoke-AzureDevOpsApi -Organization "contoso" -Project "MyProject" -ApiPath "build/builds?definitions=123&`$top=1"

.EXAMPLE
    $response = Invoke-AzureDevOpsApi -Organization "contoso" -Project "MyProject" -ApiPath "git/repositories/MyRepo/refs" -Method POST -Body $body -ApiVersion "7.1"

.EXAMPLE
    # NuGet flat container API (different hostname)
    $response = Invoke-AzureDevOpsApi -Organization "contoso" -Project "MyProject" -ApiPath "_packaging/MyFeed/nuget/v3/flat2/mypackage/index.json" -BaseUrl "https://pkgs.dev.azure.com"
#>
function Invoke-AzureDevOpsApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method = "GET",

        [Parameter(Mandatory = $false)]
        [object]$Body = $null,

        [Parameter(Mandatory = $false)]
        [string]$ApiVersion = "7.0",

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$OutFile,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 2,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer",

        [Parameter(Mandatory = $false)]
        [string]$BaseUrl = "https://dev.azure.com"
    )

    try {
        # Construct URI
        $uri = "$BaseUrl/$Organization/$Project/_apis/$ApiPath"

        # Add API version to query string
        if ($uri -notlike '*api-version=*') {
            if ($uri -match "\?") {
                $uri += "&api-version=$ApiVersion"
            } else {
                $uri += "?api-version=$ApiVersion"
            }
        }

        Write-Host "Calling API: $Method $uri using $AuthenticationType authentication"

        # Prepare authorization header based on authentication type
        $authHeader = if ($AuthenticationType -eq "Basic") {
            # For Basic auth, encode :token in base64
            $base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AccessToken"))
            "Basic $base64Token"
        }
        else {
            # Default Bearer authentication
            "Bearer $AccessToken"
        }

        # Prepare headers
        $headers = @{
            "Authorization" = $authHeader
            "Content-Type" = "application/json"
        }

        # Prepare parameters
        $params = @{
            Uri = $uri
            Headers = $headers
            Method = $Method
        }

        # Add body if provided
        if ($null -ne $Body) {
            # Ensure arrays are preserved as arrays in JSON
            # ConvertTo-Json can unwrap single-element arrays, so we need to ensure it stays as an array
            if ($Body -is [array] -and $Body.Count -eq 1) {
                # Force array serialization by wrapping in @() and using special handling
                $jsonBody = "[$($Body[0] | ConvertTo-Json -Depth 10 -Compress)]"
            } else {
                $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
            }
            Write-Host "Request Body: $jsonBody"
            $params.Body = $jsonBody
        }

        # Add OutFile if provided
        if ($OutFile) {
            $params.OutFile = $OutFile
        }

        # Retry logic with exponential backoff
        $attempt = 0
        $success = $false
        $lastError = $null

        while (-not $success -and $attempt -le $MaxRetries) {
            try {
                $attempt++

                if ($attempt -gt 1) {
                    $delay = [Math]::Pow(2, $attempt - 2) * $RetryDelaySeconds
                    Write-Host "Retry attempt $attempt of $MaxRetries after $delay seconds..."
                    Start-Sleep -Seconds $delay
                }

                Write-Host "Calling API (attempt $attempt): $Method $uri"

                # Invoke REST API
                if ($OutFile) {
                    Write-Host "Downloading to file: $OutFile"
                    Invoke-RestMethod @params

                    # Return file info
                    if (Test-Path $OutFile) {
                        $fileInfo = Get-Item $OutFile
                        Write-Host "File downloaded successfully: $($fileInfo.Length) bytes"
                        return @{
                            FilePath = $fileInfo.FullName
                            FileName = $fileInfo.Name
                            Size = $fileInfo.Length
                            Downloaded = $true
                        }
                    }
                    else {
                        throw "File download failed: File not found at $OutFile"
                    }
                }
                else {
                    # Invoke API normally
                    $response = Invoke-RestMethod @params
                    $success = $true
                    return $response
                }
            }
            catch {
                $lastError = $_
                $statusCode = $_.Exception.Response.StatusCode.value__

                # Try to read the error response body for more details
                $errorDetails = ""

                # First try ErrorDetails.Message which PowerShell populates for REST API errors
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                    $errorDetails = " - API Response: $($_.ErrorDetails.Message)"
                }
                # Fallback to reading response stream
                elseif ($_.Exception.Response) {
                    try {
                        $stream = $_.Exception.Response.GetResponseStream()
                        $stream.Position = 0
                        $reader = New-Object System.IO.StreamReader($stream)
                        $responseBody = $reader.ReadToEnd()
                        $reader.Close()
                        if ($responseBody) {
                            $errorDetails = " - API Response: $responseBody"
                        }
                    }
                    catch {
                        # Ignore errors reading response body
                    }
                }

                # Check if error is retryable (transient errors)
                $retryableErrors = @(408, 429, 500, 502, 503, 504)
                $shouldRetry = ($statusCode -in $retryableErrors) -or
                               ($_.Exception.Message -match "timeout|timed out") -or
                               ($_.Exception.Message -match "connection")

                if (-not $shouldRetry -or $attempt -gt $MaxRetries) {
                    # Non-retryable error or max retries reached
                    $errorMessage = "Azure DevOps API call failed for $Method $uri"
                    if ($statusCode) {
                        $errorMessage += " - Status Code: $statusCode"
                    }
                    if ($_.Exception.Response.StatusDescription) {
                        $errorMessage += " - $($_.Exception.Response.StatusDescription)"
                    }
                    $errorMessage += " - Error: $($_.Exception.Message)"
                    $errorMessage += $errorDetails

                    Write-Error $errorMessage
                    throw
                }

                Write-Warning "Transient error occurred (HTTP $statusCode): $($_.Exception.Message)"
            }
        }

        # If we get here, all retries failed
        if ($lastError) {
            $errorMessage = "Azure DevOps API call failed after $MaxRetries retries for $Method $uri - Error: $($lastError.Exception.Message)"
            Write-Error $errorMessage
            throw $lastError
        }
    }
    catch {
        # Top-level catch for any unexpected errors
        $errorMessage = "Unexpected error in Invoke-AzureDevOpsApi for $Method ${uri}: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}

<#
.SYNOPSIS
    Sets an Azure Pipelines variable for use in subsequent tasks.

.DESCRIPTION
    Emits the ##vso[task.setvariable] logging command to set a pipeline variable.
    Supports output variables (for cross-job access) and secret variables.

.PARAMETER Name
    Variable name to set

.PARAMETER Value
    Variable value

.PARAMETER IsOutput
    Mark the variable as an output variable for cross-job/stage access

.PARAMETER IsSecret
    Mark the variable as a secret (value masked in logs)

.EXAMPLE
    Set-PipelineVariable -Name "BuildVersion" -Value "1.2.3"

.EXAMPLE
    Set-PipelineVariable -Name "BuildVersion" -Value "1.2.3" -IsOutput
#>
function Set-PipelineVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [switch]$IsOutput,

        [Parameter(Mandatory = $false)]
        [switch]$IsSecret
    )

    $command = "##vso[task.setvariable variable=$Name"

    Write-Host "Setting pipeline variable: $Name"

    if ($IsOutput) {
        $command += ";isOutput=true"
        Write-Host " - Marked as output variable"
    }

    if ($IsSecret) {
        $command += ";issecret=true"
        Write-Host " - Marked as secret variable"
        Write-Host " - Value: ***"
    }
    else {
        Write-Host " - Value: $Value"
    }

    $command += "]$Value"

    Write-Host $command
}

Export-ModuleMember -Function Invoke-AzureDevOpsApi, Set-PipelineVariable
