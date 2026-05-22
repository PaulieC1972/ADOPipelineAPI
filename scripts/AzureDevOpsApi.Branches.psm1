# AzureDevOpsApi.Branches.psm1
# Branch-related functions for Azure DevOps

<#
.SYNOPSIS
    Gets information about a specific branch in an Azure DevOps repository.

.DESCRIPTION
    Retrieves branch details (name, object ID, URL) from the specified Azure DevOps repository using the Git Refs API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER BranchName
    Branch name to look up (without refs/heads/ prefix)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = Get-Branch -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -BranchName "main"
#>
function Get-Branch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $apiPath = "git/repositories/$Repository/refs?filter=heads/$BranchName"
        Write-Host "Getting branch information for: $BranchName"

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($response.value -and $response.value.Count -gt 0) {
            $branch = $response.value[0]
            Write-Host "Found branch: $($branch.name)" -ForegroundColor Green
            return @{
                Success  = $true
                Name     = $branch.name
                ObjectId = $branch.objectId
                Url      = $branch.url
            }
        }
        else {
            Write-Warning "Branch '$BranchName' not found"
            return @{
                Success = $false
                Name    = $BranchName
            }
        }
    }
    catch {
        Write-Error "Error getting branch information: $_"
        throw
    }
}


<#
.SYNOPSIS
    Gets a list of branches in an Azure DevOps repository.

.DESCRIPTION
    Retrieves all branches or branches matching a filter from the specified Azure DevOps repository using the Git Refs API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER Filter
    Optional filter string to match branch names

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = Get-Branches -Organization "contoso" -Project "MyProject" -Repository "MyRepo"

.EXAMPLE
    $result = Get-Branches -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -Filter "feature/"
#>
function Get-Branches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $false)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        if ($Filter) {
            $apiPath = "git/repositories/$Repository/refs?filter=heads/$Filter"
            Write-Host "Getting branches matching filter: $Filter"
        }
        else {
            $apiPath = "git/repositories/$Repository/refs?filter=heads/"
            Write-Host "Getting all branches"
        }

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($response.value -and $response.value.Count -gt 0) {
            Write-Host "Found $($response.value.Count) branch(es)" -ForegroundColor Green
            return @{
                Success  = $true
                Count    = $response.value.Count
                Branches = $response.value
            }
        }
        else {
            $filterMsg = if ($Filter) { " matching filter '$Filter'" } else { "" }
            Write-Warning "No branches found$filterMsg"
            return @{
                Success  = $false
                Count    = 0
                Branches = @()
            }
        }
    }
    catch {
        Write-Error "Error getting branches: $_"
        throw
    }
}


<#
.SYNOPSIS
    Creates a new branch in an Azure DevOps repository.

.DESCRIPTION
    Creates a new branch from a source branch in the specified Azure DevOps repository using the Git Refs API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER BranchName
    Name of the new branch to create (without refs/heads/ prefix)

.PARAMETER SourceBranch
    Name of the source branch to branch from (without refs/heads/ prefix)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = New-Branch -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -BranchName "feature/new" -SourceBranch "main"
#>
function New-Branch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [Parameter(Mandatory = $true)]
        [string]$SourceBranch,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        # Get the source branch commit SHA
        $sourceBranchRef = "$SourceBranch"
        $apiPath = "git/repositories/$Repository/refs?filter=heads/$SourceBranch"

        Write-Host "Getting source branch reference: $sourceBranchRef"

        $sourceRefResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if (-not $sourceRefResponse.value -or $sourceRefResponse.value.Count -eq 0) {
            Write-Warning "Source branch '$SourceBranch' not found with filter. Trying to list all branches..."
            # Try getting all refs to see what's available
            $allRefsPath = "git/repositories/$Repository/refs?filter=heads/"
            $allRefsResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $allRefsPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

            Write-Host "API Response count: $($allRefsResponse.value.Count)"
            if ($allRefsResponse.value) {
                Write-Host "Available branches ($($allRefsResponse.value.Count) total):"
                foreach ($ref in $allRefsResponse.value) {
                    Write-Host "  - Name: $($ref.name), ObjectId: $($ref.objectId)"
                }
            }
            else {
                Write-Host "No branches returned from API or response is null"
                Write-Host "Response object: $($allRefsResponse | ConvertTo-Json -Depth 3)"
            }

            throw "Source branch '$SourceBranch' not found. Please check available branches above and update the SourceBranch parameter."
        }

        $sourceCommitId = $sourceRefResponse.value[0].objectId
        Write-Host "Source branch commit ID: $sourceCommitId"

        # Create new branch
        $newBranchRef = "refs/heads/$BranchName"
        $apiPath = "git/repositories/$Repository/refs"

        $body = @(
            @{
                name        = $newBranchRef
                oldObjectId = "0000000000000000000000000000000000000000"
                newObjectId = $sourceCommitId
            }
        )

        Write-Host "Creating branch: $newBranchRef"
        Write-Host "Request body: $($body | ConvertTo-Json -Depth 10)"

        $createResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method POST -Body $body -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($createResponse.value -and $createResponse.value[0].success) {
            Write-Host "Successfully created branch: $BranchName" -ForegroundColor Green
            return @{
                Success      = $true
                BranchName   = $BranchName
                BranchRef    = $newBranchRef
                CommitId     = $sourceCommitId
            }
        }
        else {
            throw "Failed to create branch. Response: $($createResponse | ConvertTo-Json -Depth 10)"
        }
    }
    catch {
        Write-Error "Error creating branch: $_"
        throw
    }
}

<#
.SYNOPSIS
    Deletes a branch from an Azure DevOps Git repository.

.DESCRIPTION
    Removes a branch by its name. If the branch does not exist, returns
    gracefully without error. Uses the Git Refs API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER BranchName
    Branch name to delete (without refs/heads/ prefix)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    Remove-Branch -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -BranchName "feature/release/1.0.0"
#>
function Remove-Branch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $existing = Get-Branch -Organization $Organization -Project $Project `
            -Repository $Repository -BranchName $BranchName `
            -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if (-not $existing.Success) {
            Write-Host "Branch '$BranchName' does not exist — nothing to delete"
            return @{ Success = $true; Deleted = $false }
        }

        $body = @(
            @{
                name        = "refs/heads/$BranchName"
                oldObjectId = $existing.ObjectId
                newObjectId = "0000000000000000000000000000000000000000"
            }
        )

        Write-Host "Deleting branch: $BranchName"

        Invoke-AzureDevOpsApi -Organization $Organization -Project $Project `
            -ApiPath "git/repositories/$Repository/refs" -Method POST `
            -Body $body -AccessToken $AccessToken -AuthenticationType $AuthenticationType `
            -ApiVersion "7.1" | Out-Null

        Write-Host "Successfully deleted branch: $BranchName" -ForegroundColor Green
        return @{ Success = $true; Deleted = $true }
    }
    catch {
        Write-Error "Error deleting branch $BranchName : $_"
        throw
    }
}

Export-ModuleMember -Function Get-Branch, Get-Branches, New-Branch, Remove-Branch