# AzureDevOpsApi.Commits.psm1
# Commit-related functions for Azure DevOps

<#
.SYNOPSIS
    Gets detailed information about a specific commit.

.DESCRIPTION
    Retrieves commit details including author, committer, push information, and comment
    for the given commit ID using the Azure DevOps Git Commits API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER RepositoryId
    Repository name or ID

.PARAMETER CommitId
    Full SHA of the commit to retrieve

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $commit = Get-Commit -Organization "contoso" -Project "MyProject" -RepositoryId "MyRepo" -CommitId "abc123"
#>
function Get-Commit {
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
        [string]$CommitId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting commit ID: $CommitId"

        $apiPath = "git/repositories/$RepositoryId/commits/$CommitId"
        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        return @{
            Id = $response.commitId
            Comment = $response.comment
            Author = @{
                Name = $response.author.name
                email = $response.author.email
                Date = $response.author.date
            }
            Committer = @{
                Name = $response.committer.name
                email = $response.committer.email
                Date = $response.committer.date
            }
            Push = @{
                PushId = $response.push.pushId
                Date = $response.push.date
                PushedById = $response.push.pushedBy.id
                PushedByUniqueName = $response.push.pushedBy.uniqueName
                PushedByDisplayName = $response.push.pushedBy.displayName
            }
        }
    }
    catch {
        $errorMessage = "Failed to get commit ID: $CommitId from repository: $RepositoryId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}


<#
.SYNOPSIS
    Compares two branches and returns the commits that differ.

.DESCRIPTION
    Uses the Azure DevOps Git CommitsBatch API to find commits in the target branch that
    are not in the base branch. Optionally filters by file path and can fetch full commit
    comments for truncated entries.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER RepositoryId
    Repository name or ID

.PARAMETER BaseBranch
    Base branch name to compare against (with or without refs/heads/ prefix)

.PARAMETER TargetBranch
    Target branch name containing the new commits (with or without refs/heads/ prefix)

.PARAMETER ItemPath
    Optional file path filter to scope the comparison

.PARAMETER IncludeFullComment
    Fetch full commit comments for entries that were truncated by the API

.PARAMETER top
    Maximum number of commits to return (default: 1000)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $commits = Compare-Branches -Organization "contoso" -Project "MyProject" -RepositoryId "MyRepo" -BaseBranch "main" -TargetBranch "feature/work"

.EXAMPLE
    $commits = Compare-Branches -Organization "contoso" -Project "MyProject" -RepositoryId "MyRepo" -BaseBranch "main" -TargetBranch "feature/work" -ItemPath "src/" -IncludeFullComment
#>
function Compare-Branches {
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
        [string]$BaseBranch,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetBranch,

        [Parameter(Mandatory = $false)]
        [string]$ItemPath = $null,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeFullComment,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [int]$top = 1000,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Comparing branches: Base='$BaseBranch' vs Target='$TargetBranch'"

        # Strip refs/heads/ prefix if present (commitsBatch API expects branch name without prefix)
        $baseVersion = $BaseBranch -replace '^refs/heads/', ''
        $targetVersion = $TargetBranch -replace '^refs/heads/', ''

        Write-Host "Using BaseVersion: $baseVersion"
        Write-Host "Using TargetVersion: $targetVersion"

        # Use commitsBatch API to get commits in target branch that are not in base branch
        $apiPath = "git/repositories/$RepositoryId/commitsBatch"
        $requestBody = @{
            itemVersion = @{
                versionType = "branch"
                version = $targetVersion
            }
            compareVersion = @{
                versionType = "branch"
                version = $baseVersion
            }
            '$top' = $top
        }

        # Add itemPath filter if specified
        if (-not [string]::IsNullOrWhiteSpace($ItemPath)) {
            Write-Host "Filtering commits to path: $ItemPath"
            $requestBody['itemPath'] = $ItemPath
        }

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method "POST" -Body $requestBody -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($null -eq $response -or $null -eq $response.value -or $response.value.Count -eq 0) {
            Write-Host "No differences found between branches"
            return @()
        }

        Write-Host "Found $($response.value.Count) commits"

        # Process each commit and get detailed information
        $commits = @()
        foreach ($commit in $response.value) {
            # If full comment requested, fetch individual commit details only if the API indicates truncation
            $fullComment = $commit.comment
            if ($IncludeFullComment -and $commit.commentTruncated -eq $true) {
                try {
                    Write-Host "Fetching full details for commit $($commit.commitId)"
                    $commitDetailPath = "git/repositories/$RepositoryId/commits/$($commit.commitId)"
                    $commitDetail = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $commitDetailPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"
                    $fullComment = $commitDetail.comment
                }
                catch {
                    Write-Warning "Failed to fetch full comment for commit $($commit.commitId): $($_.Exception.Message)"
                    $fullComment = $commit.comment
                }
            }

            $commitInfo = @{
                CommitId = $commit.commitId
                Comment = $fullComment
                Description = if ($commit.comment) {
                    # Split comment into first line (title) and rest (description)
                    $lines = $commit.comment -split "`n", 2
                    if ($lines.Count -gt 1) { $lines[1].Trim() } else { "" }
                } else { "" }
                Author = @{
                    Name = $commit.author.name
                    Email = $commit.author.email
                    Date = $commit.author.date
                }
                Committer = @{
                    Name = $commit.committer.name
                    Email = $commit.committer.email
                    Date = $commit.committer.date
                }
                Url = $commit.url
                PullRequestId = $null
            }

            # Try to extract PR number from commit comment
            if ($commit.comment -match "Merged PR (\d+):") {
                $commitInfo.PullRequestId = $Matches[1]
            }
            # Alternative pattern: "Pull request #123"
            elseif ($commit.comment -match "Pull request #(\d+)") {
                $commitInfo.PullRequestId = $Matches[1]
            }
            # Alternative pattern: "(#123)"
            elseif ($commit.comment -match "\(#(\d+)\)") {
                $commitInfo.PullRequestId = $Matches[1]
            }

            $commits += $commitInfo
        }

        return $commits
    }
    catch {
        $errorMessage = "Failed to compare branches '$BaseBranch' and '$TargetBranch' in repository: $RepositoryId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}


<#
.SYNOPSIS
    Creates a new commit with file changes in an Azure DevOps repository.

.DESCRIPTION
    Pushes a commit that edits a file on the specified branch using the Azure DevOps
    Git Push API. Requires author name and email for the commit metadata.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER BranchName
    Target branch name (without refs/heads/ prefix)

.PARAMETER FilePath
    Path to the file in the repository (e.g., "src/CHANGELOG.md")

.PARAMETER FileContent
    New content for the file

.PARAMETER CommitMessage
    Commit message

.PARAMETER AuthorName
    Author name for the commit

.PARAMETER AuthorEmail
    Author email for the commit

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = New-Commit -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -BranchName "feature/update" -FilePath "README.md" -FileContent $content -CommitMessage "Update README" -AuthorName "CI Bot" -AuthorEmail "ci@example.com"
#>
function New-Commit {
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
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$FileContent,

        [Parameter(Mandatory = $true)]
        [string]$CommitMessage,

        [Parameter(Mandatory = $true)]
        [string]$AuthorName,

        [Parameter(Mandatory = $true)]
        [string]$AuthorEmail,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        # Get current branch commit SHA
        $branchRef = "refs/heads/$BranchName"
        $apiPath = "git/repositories/$Repository/refs?filter=heads/$BranchName"

        Write-Host "Getting current branch reference: $branchRef"

        $branchRefResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if (-not $branchRefResponse.value -or $branchRefResponse.value.Count -eq 0) {
            throw "Branch '$BranchName' not found"
        }

        $oldObjectId = $branchRefResponse.value[0].objectId
        Write-Host "Current branch commit ID: $oldObjectId"

        # Create commit with file change
        $apiPath = "git/repositories/$Repository/pushes"

        $body = @{
            refUpdates = @(
                @{
                    name        = $branchRef
                    oldObjectId = $oldObjectId
                }
            )
            commits = @(
                @{
                    comment = $CommitMessage
                    author = @{
                        name = $AuthorName
                        email = $AuthorEmail
                        date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    }
                    changes = @(
                        @{
                            changeType = "edit"
                            item       = @{
                                path = "/$FilePath"
                            }
                            newContent = @{
                                content     = $FileContent
                                contentType = "rawtext"
                            }
                        }
                    )
                }
            )
        }

        Write-Host "Committing changes to: $FilePath"

        $pushResponse = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method POST -Body $body -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($pushResponse.commits -and $pushResponse.commits.Count -gt 0) {
            $commitId = $pushResponse.commits[0].commitId
            Write-Host "Successfully committed changes. Commit ID: $commitId" -ForegroundColor Green
            return @{
                Success  = $true
                CommitId = $commitId
            }
        }
        else {
            throw "Failed to commit changes. Response: $($pushResponse | ConvertTo-Json -Depth 10)"
        }
    }
    catch {
        Write-Error "Error committing changes: $_"
        throw
    }
}


<#
.SYNOPSIS
    Tests whether one commit is an ancestor of another.

.DESCRIPTION
    Uses the Azure DevOps Git Merge Bases API to determine if CommitId is an ancestor
    of DescendantCommitId. Returns the ancestry result and the merge base commit IDs.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER CommitId
    The potential ancestor commit SHA

.PARAMETER DescendantCommitId
    The potential descendant commit SHA

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = Test-CommitAncestry -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -CommitId "abc123" -DescendantCommitId "def456"
    if ($result.IsAncestor) { Write-Host "Commit is an ancestor" }
#>
function Test-CommitAncestry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$CommitId,

        [Parameter(Mandatory = $true)]
        [string]$DescendantCommitId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        # Merge Bases API: GET repos/{repo}/commits/{commitId}/mergebases?otherCommitId={otherCommitId}
        $apiPath = "git/repositories/$Repository/commits/$DescendantCommitId/mergebases?otherCommitId=$CommitId"

        Write-Host "Checking if $CommitId is an ancestor of $DescendantCommitId"

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        # If CommitId appears in the merge bases, it is an ancestor of DescendantCommitId
        $isAncestor = $false
        if ($response.value) {
            $isAncestor = ($response.value | Where-Object { $_.commitId -eq $CommitId }) -ne $null
        }

        Write-Host "Result: CommitId $CommitId is$(if (-not $isAncestor) { ' NOT' }) an ancestor of $DescendantCommitId"

        return @{
            Success    = $true
            IsAncestor = $isAncestor
            MergeBases = if ($response.value) { $response.value | ForEach-Object { $_.commitId } } else { @() }
        }
    }
    catch {
        Write-Error "Error checking commit ancestry: $_"
        throw
    }
}
Export-ModuleMember -Function Get-Commit, Compare-Branches, New-Commit, Test-CommitAncestry