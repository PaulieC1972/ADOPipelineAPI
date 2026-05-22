# AzureDevOpsApi.Pipelines.psm1
# Pipeline run operations for Azure DevOps

<#
.SYNOPSIS
    Triggers a pipeline run in Azure DevOps.

.DESCRIPTION
    Queues a new run of the specified pipeline definition using the Pipelines API.
    Supports specifying a source branch and template parameters.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER PipelineId
    Pipeline definition ID to trigger

.PARAMETER Branch
    Source branch for the run (with or without refs/heads/ prefix)

.PARAMETER TemplateParameters
    Hashtable of template parameters to pass to the pipeline

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $run = Invoke-PipelineRun -Organization "contoso" -Project "MyProject" `
        -PipelineId 10957 -Branch "feature/release/1.0.0" `
        -TemplateParameters @{ RunAutomation = "true" }

.EXAMPLE
    $run = Invoke-PipelineRun -Organization "contoso" -Project "MyProject" `
        -PipelineId 12345 -Branch "release/main"
#>
function Invoke-PipelineRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [int]$PipelineId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch,

        [Parameter(Mandatory = $false)]
        [hashtable]$TemplateParameters = @{},

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $branchRef = if ($Branch -like "refs/heads/*") { $Branch } else { "refs/heads/$Branch" }

        $body = @{
            resources = @{
                repositories = @{
                    self = @{ refName = $branchRef }
                }
            }
        }

        if ($TemplateParameters.Count -gt 0) {
            $body.templateParameters = $TemplateParameters
        }

        $apiPath = "pipelines/$PipelineId/runs"

        Write-Host "Triggering pipeline $PipelineId on branch $Branch..."

        $response = Invoke-AzureDevOpsApi `
            -Organization $Organization `
            -Project $Project `
            -ApiPath $apiPath `
            -Method POST `
            -Body $body `
            -AccessToken $AccessToken `
            -AuthenticationType $AuthenticationType `
            -ApiVersion "6.0-preview.1"

        Write-Host "Pipeline run triggered: ID $($response.id)" -ForegroundColor Green

        return @{
            Success = $true
            RunId   = $response.id
            Name    = $response.name
            State   = $response.state
            Url     = $response._links.web.href
        }
    }
    catch {
        Write-Error "Failed to trigger pipeline $PipelineId : $_"
        throw
    }
}

<#
.SYNOPSIS
    Gets the status of a pipeline run.

.DESCRIPTION
    Retrieves the current state and result of a pipeline run using the Pipelines Runs API.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER PipelineId
    Pipeline definition ID

.PARAMETER RunId
    Pipeline run ID to check

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $status = Get-PipelineRunStatus -Organization "contoso" -Project "MyProject" `
        -PipelineId 10957 -RunId 12345678
    Write-Host "State: $($status.State), Result: $($status.Result)"
#>
function Get-PipelineRunStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [int]$PipelineId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [int]$RunId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        $apiPath = "pipelines/$PipelineId/runs/$RunId"

        $response = Invoke-AzureDevOpsApi `
            -Organization $Organization `
            -Project $Project `
            -ApiPath $apiPath `
            -AccessToken $AccessToken `
            -AuthenticationType $AuthenticationType

        return @{
            RunId  = $response.id
            State  = $response.state
            Result = $response.result
            Url    = $response._links.web.href
        }
    }
    catch {
        Write-Error "Failed to get pipeline run status for $PipelineId/$RunId : $_"
        throw
    }
}

<#
.SYNOPSIS
    Waits for a pipeline run to complete, polling at a specified interval.

.DESCRIPTION
    Polls the Pipelines Runs API at regular intervals until the run reaches
    a 'completed' state. Returns the final state and result.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER PipelineId
    Pipeline definition ID

.PARAMETER RunId
    Pipeline run ID to wait for

.PARAMETER PollIntervalSeconds
    Seconds between status polls (default: 300 = 5 minutes)

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = Wait-PipelineRun -Organization "contoso" -Project "MyProject" `
        -PipelineId 10957 -RunId 12345678 -PollIntervalSeconds 300
    if ($result.Result -eq 'succeeded') { Write-Host "Pipeline passed!" }

.EXAMPLE
    $run = Invoke-PipelineRun -Organization "contoso" -Project "MyProject" -PipelineId 10957 -Branch "main"
    $result = Wait-PipelineRun -Organization "contoso" -Project "MyProject" `
        -PipelineId 10957 -RunId $run.RunId
#>
function Wait-PipelineRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [int]$PipelineId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [int]$RunId,

        [Parameter(Mandatory = $false)]
        [int]$PollIntervalSeconds = 300,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    Write-Host "Waiting for pipeline $PipelineId run $RunId to complete (polling every $PollIntervalSeconds s)..."

    $consecutiveErrors = 0
    $maxConsecutiveErrors = 5

    while ($true) {
        try {
            $status = Get-PipelineRunStatus `
                -Organization $Organization `
                -Project $Project `
                -PipelineId $PipelineId `
                -RunId $RunId `
                -AccessToken $AccessToken `
                -AuthenticationType $AuthenticationType

            $consecutiveErrors = 0

            Write-Host ("[{0}] State: {1} | Result: {2}" -f (Get-Date -Format 'HH:mm:ss'), $status.State, $status.Result)

            if ($status.State -eq 'completed') {
                if ($status.Result -eq 'succeeded') {
                    Write-Host "Pipeline run $RunId completed successfully" -ForegroundColor Green
                }
                else {
                    Write-Warning "Pipeline run $RunId completed with result: $($status.Result)"
                    if ($status.Url) {
                        Write-Host "Review: $($status.Url)"
                    }
                }
                return $status
            }
        }
        catch {
            $consecutiveErrors++
            Write-Warning "Failed to poll pipeline status (attempt $consecutiveErrors/$maxConsecutiveErrors): $_"
            if ($consecutiveErrors -ge $maxConsecutiveErrors) {
                throw "Pipeline polling failed after $maxConsecutiveErrors consecutive errors: $_"
            }
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }
}

<#
.SYNOPSIS
    Cancels a running Azure DevOps build.

.DESCRIPTION
    Sets the build status to 'cancelling' via the Builds API, causing
    the pipeline to cancel gracefully.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER BuildId
    Build ID to cancel

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    Stop-Build -Organization "contoso" -Project "MyProject" -BuildId 12345678
#>
function Stop-Build {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [int]$BuildId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $body = @{ status = "cancelling" }

        Write-Host "Cancelling build $BuildId..."

        Invoke-AzureDevOpsApi `
            -Organization $Organization `
            -Project $Project `
            -ApiPath "build/builds/$BuildId" `
            -Method PATCH `
            -Body $body `
            -AccessToken $AccessToken `
            -AuthenticationType $AuthenticationType | Out-Null

        Write-Host "Build $BuildId cancellation requested" -ForegroundColor Yellow
        return @{ Success = $true; BuildId = $BuildId }
    }
    catch {
        Write-Error "Failed to cancel build $BuildId : $_"
        throw
    }
}

Export-ModuleMember -Function Invoke-PipelineRun, Get-PipelineRunStatus, Wait-PipelineRun, Stop-Build
