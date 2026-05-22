# AzureDevOpsApi.PullRequests.psm1
# Pull Request-related functions for Azure DevOps

<#
.SYNOPSIS
    Gets details of a specific pull request.

.DESCRIPTION
    Retrieves pull request details including title, status, source/target branches,
    creator information, and changed files using the Azure DevOps Git Pull Requests API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER RepositoryId
    Repository name or ID

.PARAMETER PullRequestId
    Pull request ID to retrieve

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $pr = Get-PullRequest -Organization "contoso" -Project "MyProject" -RepositoryId "MyRepo" -PullRequestId 123
#>
function Get-PullRequest {
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
        [string]$RepositoryId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [int]$PullRequestId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting pull request ID: $PullRequestId from repository: $RepositoryId"

        # Get PR details
        $apiPath = "git/repositories/$RepositoryId/pullrequests/$PullRequestId"
        $pr = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        # Get PR changes (files)
        $changesApiPath = "git/repositories/$RepositoryId/pullrequests/$PullRequestId/iterations/1/changes"
        $changes = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $changesApiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        # Extract file paths from changes
        $changedFiles = @()
        if ($changes.changeEntries) {
            $changedFiles = $changes.changeEntries | ForEach-Object { $_.item.path }
        }

        return @{
            PullRequestId = $pr.pullRequestId
            Title = $pr.title
            Description = $pr.description
            Status = $pr.status
            CreatedBy = @{
                DisplayName = $pr.createdBy.displayName
                UniqueName = $pr.createdBy.uniqueName
                Id = $pr.createdBy.id
            }
            SourceBranch = $pr.sourceRefName
            TargetBranch = $pr.targetRefName
            CreationDate = $pr.creationDate
            ClosedDate = $pr.closedDate
            Url = $pr.url
            ChangedFiles = $changedFiles
            FileCount = $changedFiles.Count
        }
    }
    catch {
        $errorMessage = "Failed to get pull request ID: $PullRequestId from repository: $RepositoryId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}


<#
.SYNOPSIS
    Creates a new pull request in an Azure DevOps repository.

.DESCRIPTION
    Creates a pull request from a source branch to a target branch, with optional
    work item linking and auto-complete, using the Azure DevOps Git Pull Requests API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER SourceBranch
    Source branch name (without refs/heads/ prefix)

.PARAMETER TargetBranch
    Target branch name (without refs/heads/ prefix, default: "main")

.PARAMETER Title
    Pull request title

.PARAMETER Description
    Pull request description (default: empty)

.PARAMETER WorkItemIds
    Optional array of work item IDs to link to the pull request

.PARAMETER AutoComplete
    Whether to set auto-complete on the pull request (default: false)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = New-PullRequest -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -SourceBranch "feature/work" -TargetBranch "main" -Title "My PR" -AutoComplete $true
#>
function New-PullRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$SourceBranch,

        [Parameter(Mandatory = $false)]
        [string]$TargetBranch = "main",

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [string[]]$WorkItemIds = @(),

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [bool]$AutoComplete = $false,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $apiPath = "git/repositories/$Repository/pullrequests"

        $body = @{
            sourceRefName = "refs/heads/$SourceBranch"
            targetRefName = "refs/heads/$TargetBranch"
            title         = $Title
            description   = $Description
        }

        # Add work items if provided
        if ($WorkItemIds -and $WorkItemIds.Count -gt 0) {
            $body.workItemRefs = @()
            foreach ($workItemId in $WorkItemIds) {
                $body.workItemRefs += @{
                    id = $workItemId
                }
            }
        }

        Write-Host "Creating pull request: $Title"
        Write-Host "  Source: $SourceBranch"
        Write-Host "  Target: $TargetBranch"

        $prResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method POST -Body $body -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($prResponse.pullRequestId) {
            $prId = $prResponse.pullRequestId
            $prUrl = $prResponse.url

            Write-Host "Successfully created pull request #$prId" -ForegroundColor Green
            Write-Host "PR URL: https://dev.azure.com/$Organization/$Project/_git/$Repository/pullrequest/$prId"

            # Set auto-complete if requested
            if ($AutoComplete) {
                Write-Host "Setting auto-complete on PR..."
                Set-PullRequestAutoComplete -Organization $Organization -Project $Project -Repository $Repository -PullRequestId $prId -AccessToken $AccessToken -AuthenticationType $AuthenticationType
            }

            return @{
                Success       = $true
                PullRequestId = $prId
                Url           = $prUrl
            }
        }
        else {
            throw "Failed to create pull request. Response: $($prResponse | ConvertTo-Json -Depth 10)"
        }
    }
    catch {
        Write-Error "Error creating pull request: $_"
        throw
    }
}


<#
.SYNOPSIS
    Sets auto-complete on a pull request.

.DESCRIPTION
    Configures a pull request to automatically complete when all policies are satisfied,
    using the PR creator as the auto-complete initiator.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER PullRequestId
    Pull request ID to set auto-complete on

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    Set-PullRequestAutoComplete -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -PullRequestId 123
#>
function Set-PullRequestAutoComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [int]$PullRequestId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        $apiPath = "git/repositories/$Repository/pullrequests/$PullRequestId"

        # Get current PR to get the creator info
        $prResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        $body = @{
            autoCompleteSetBy = @{
                id = $prResponse.createdBy.id
            }
        }

        $updateResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method PATCH -Body $body -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"
        Write-Host "Auto-complete set successfully" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to set auto-complete: $_"
    }
}


<#
.SYNOPSIS
    Sets a vote on a pull request.

.DESCRIPTION
    Submits a review vote on the specified pull request. Vote values: 10 (Approved),
    5 (Approved with suggestions), 0 (No vote), -5 (Waiting for author), -10 (Rejected).
    If no ReviewerId is provided, the PR creator's identity is used.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER PullRequestId
    Pull request ID to vote on

.PARAMETER ReviewerId
    Optional reviewer identity ID; defaults to the PR creator

.PARAMETER Vote
    Vote value: 10 (Approved), 5 (Approved with suggestions), 0 (No vote), -5 (Waiting for author), -10 (Rejected). Default: 10

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    Set-PullRequestVote -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -PullRequestId 123 -Vote 10
#>
function Set-PullRequestVote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [int]$PullRequestId,

        [Parameter(Mandatory = $false)]
        [string]$ReviewerId,

        [Parameter(Mandatory = $false)]
        [ValidateSet(10, 5, 0, -5, -10)]
        [int]$Vote = 10,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        # If no reviewer ID provided, get the PR creator's identity
        if ([string]::IsNullOrEmpty($ReviewerId)) {
            $prApiPath = "git/repositories/$Repository/pullrequests/$PullRequestId"
            $prResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $prApiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"
            $ReviewerId = $prResponse.createdBy.id
            Write-Host "Using PR creator as reviewer: $($prResponse.createdBy.displayName) ($ReviewerId)"
        }

        $voteDescription = switch ($Vote) {
            10  { "Approved" }
            5   { "Approved with suggestions" }
            0   { "No vote" }
            -5  { "Waiting for author" }
            -10 { "Rejected" }
        }

        Write-Host "Setting vote on PR #$PullRequestId to: $voteDescription ($Vote)"

        $apiPath = "git/repositories/$Repository/pullrequests/$PullRequestId/reviewers/$ReviewerId"

        $body = @{
            vote = $Vote
        }

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method PUT -Body $body -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        Write-Host "Vote set successfully: $voteDescription" -ForegroundColor Green
        return @{
            Success     = $true
            Vote        = $Vote
            ReviewerId  = $ReviewerId
            Description = $voteDescription
        }
    }
    catch {
        Write-Error "Error setting pull request vote: $_"
        throw
    }
}
Export-ModuleMember -Function Get-PullRequest, New-PullRequest, Set-PullRequestAutoComplete, Set-PullRequestVote