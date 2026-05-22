# AzureDevOpsApi.Builds.psm1
# Build-related functions for Azure DevOps

<#
.SYNOPSIS
    Gets the latest successful build for a specific build definition.

.DESCRIPTION
    Retrieves the most recent completed and succeeded build for the given definition ID
    using the Azure DevOps Builds API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER DefinitionId
    Build definition ID to query

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $build = Get-LatestSuccessfulBuild -Organization "contoso" -Project "MyProject" -DefinitionId 123
#>
function Get-LatestSuccessfulBuild {
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
        [int]$DefinitionId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting latest successful build for definition ID: $DefinitionId"

        $apiPath = "build/builds?definitions=$DefinitionId&statusFilter=completed&resultFilter=succeeded&`$top=1"
        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if ($response.value -and $response.value.Count -gt 0) {
            $build = $response.value[0]
            Write-Host "Found build: $($build.buildNumber) (ID: $($build.id))"

            return @{
                Id = $build.id
                BuildNumber = $build.buildNumber
                SourceBranch = $build.sourceBranch
                SourceVersion = $build.sourceVersion
                Status = $build.status
                Result = $build.result
                QueueTime = $build.queueTime
                StartTime = $build.startTime
                FinishTime = $build.finishTime
                Url = $build._links.web.href
            }
        }
        else {
            Write-Warning "No successful builds found for definition ID: $DefinitionId"
            return $null
        }
    }
    catch {
        $errorMessage = "Failed to get latest successful build for definition ID: $DefinitionId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}

<#
.SYNOPSIS
    Gets the latest successful builds for a specific build definition.

.DESCRIPTION
    Retrieves the most recent completed and succeeded (optionally partially succeeded) builds
    for the given definition ID, with configurable sort order and count.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER DefinitionId
    Build definition ID to query

.PARAMETER QueryOrder
    Sort order for the results (e.g., "finishTimeDescending")

.PARAMETER Number
    Maximum number of builds to return (default: 5)

.PARAMETER IncludePartiallySucceeded
    Whether to include partially succeeded builds (default: true)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $builds = Get-LatestSuccessfulBuilds -Organization "contoso" -Project "MyProject" -DefinitionId 123 -QueryOrder "finishTimeDescending" -Number 10
#>
function Get-LatestSuccessfulBuilds {
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
        [int]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("finishTimeAscending", "finishTimeDescending", "queueTimeDescending", "queueTimeAscending", "startTimeDescending", "startTimeAscending")]
        [string]$QueryOrder,

        [Parameter(Mandatory = $false)]
        [int]$Number = 5,

        [Parameter(Mandatory = $false)]
        [boolean]$IncludePartiallySucceeded = 1,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting latest successful build for definition ID: $DefinitionId"

        $resultFilter = "succeeded"
        if ($IncludePartiallySucceeded) {
            $resultFilter = "succeeded,partiallySucceeded"
        }

        $apiPath = "build/builds?definitions=$DefinitionId&statusFilter=completed&resultFilter=$resultFilter&queryOrder=$QueryOrder&maxBuildsPerDefinition=$Number"
        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($response.value -and $response.value.Count -gt 0) {
            Write-Host "Found $($response.value.Count) build(s)"
            $builds = @()
            foreach ($build in $response.value) {
                $builds += @{
                    Id = $build.id
                    BuildNumber = $build.buildNumber
                    SourceBranch = $build.sourceBranch
                    SourceVersion = $build.sourceVersion
                    QueueTime = $build.queueTime
                    StartTime = $build.startTime
                    FinishTime = $build.finishTime
                }
            }
            return $builds
        }
        else {
            Write-Warning "No successful builds found for definition ID: $DefinitionId"
            return $null
        }
    }
    catch {
        $errorMessage = "Failed to get latest $Number successful builds for definition ID: $DefinitionId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}


<#
.SYNOPSIS
    Gets all commits associated with a specific build.

.DESCRIPTION
    Retrieves the list of commits (source changes) that were included in the given build
    using the Azure DevOps Build Changes API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER BuildId
    Build ID to query commits for

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $commits = Get-BuildCommits -Organization "contoso" -Project "MyProject" -BuildId 456
#>
function Get-BuildCommits {
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
        [int]$BuildId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting commits for build ID: $BuildId"

        $apiPath = "build/builds/$BuildId/changes"
        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if ($response.value) {
            Write-Host "Found $($response.value.Count) commit(s)"

            $commits = @()
            foreach ($change in $response.value) {
                $commits += @{
                    Id = $change.id
                    Message = $change.message
                    Author = $change.author.displayName
                    Timestamp = $change.timestamp
                    Type = $change.type
                }
            }

            return $commits
        }
        else {
            Write-Warning "No commits found for build ID: $BuildId"
            return @()
        }
    }
    catch {
        $errorMessage = "Failed to get commits for build ID: $BuildId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}

<#
.SYNOPSIS
    Gets work items associated with a specific build.

.DESCRIPTION
    Retrieves the list of work items linked to the given build using the Azure DevOps
    Build Work Items API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER BuildId
    Build ID to query work items for

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $workItems = Get-BuildWorkItems -Organization "contoso" -Project "MyProject" -BuildId 456
#>
function Get-BuildWorkItems {
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
        [int]$BuildId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting work items for build ID: $BuildId"

        $apiPath = "build/builds/$BuildId/workitems"
        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if ($response.value) {
            Write-Host "Found $($response.value.Count) work item(s)"

            $workItems = @()
            foreach ($wi in $response.value) {
                $workItems += @{
                    Id = $wi.id
                    Url = $wi.url
                }
            }

            return $workItems
        }
        else {
            Write-Warning "No work items found for build ID: $BuildId"
            return @()
        }
    }
    catch {
        $errorMessage = "Failed to get work items for build ID: $BuildId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}

<#
.SYNOPSIS
    Gets build definition details.

.DESCRIPTION
    Retrieves details about a build definition including its name, path, queue status,
    and repository information using the Azure DevOps Build Definitions API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER DefinitionId
    Build definition ID to query

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $def = Get-BuildDefinition -Organization "contoso" -Project "MyProject" -DefinitionId 123
#>
function Get-BuildDefinition {
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
        [int]$DefinitionId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting build definition ID: $DefinitionId"

        $apiPath = "build/definitions/$DefinitionId"
        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        return @{
            Id = $response.id
            Name = $response.name
            Path = $response.path
            Type = $response.type
            QueueStatus = $response.queueStatus
            Revision = $response.revision
            Repository = @{
                Id = $response.repository.id
                Type = $response.repository.type
                Name = $response.repository.name
                DefaultBranch = $response.repository.defaultBranch
            }
        }
    }
    catch {
        $errorMessage = "Failed to get build definition ID: $DefinitionId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}

<#
.SYNOPSIS
    Gets builds for a definition within an optional date range.

.DESCRIPTION
    Retrieves builds for the given definition ID, optionally filtered by minimum and maximum
    time boundaries, using the Azure DevOps Builds API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER DefinitionId
    Build definition ID to query

.PARAMETER MinTime
    Optional minimum queue/finish time filter

.PARAMETER MaxTime
    Optional maximum queue/finish time filter

.PARAMETER Top
    Maximum number of builds to return (default: 50)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $builds = Get-BuildsByDateRange -Organization "contoso" -Project "MyProject" -DefinitionId 123 -MinTime (Get-Date).AddDays(-7)
#>
function Get-BuildsByDateRange {
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
        [int]$DefinitionId,

        [Parameter(Mandatory = $false)]
        [datetime]$MinTime,

        [Parameter(Mandatory = $false)]
        [datetime]$MaxTime,

        [Parameter(Mandatory = $false)]
        [int]$Top = 50,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting builds for definition ID: $DefinitionId"

        $apiPath = "build/builds?definitions=$DefinitionId&`$top=$Top"

        if ($MinTime) {
            $minTimeStr = $MinTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $apiPath += "&minTime=$minTimeStr"
        }

        if ($MaxTime) {
            $maxTimeStr = $MaxTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $apiPath += "&maxTime=$maxTimeStr"
        }

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if ($response.value) {
            Write-Host "Found $($response.value.Count) build(s)"

            $builds = @()
            foreach ($build in $response.value) {
                $builds += @{
                    Id = $build.id
                    BuildNumber = $build.buildNumber
                    Status = $build.status
                    Result = $build.result
                    QueueTime = $build.queueTime
                    StartTime = $build.startTime
                    FinishTime = $build.finishTime
                    SourceBranch = $build.sourceBranch
                }
            }

            return $builds
        }
        else {
            Write-Warning "No builds found"
            return @()
        }
    }
    catch {
        $dateRangeInfo = ""
        if ($MinTime) { $dateRangeInfo += " MinTime: $($MinTime.ToString('yyyy-MM-dd HH:mm:ss'))" }
        if ($MaxTime) { $dateRangeInfo += " MaxTime: $($MaxTime.ToString('yyyy-MM-dd HH:mm:ss'))" }
        $errorMessage = "Failed to get builds for definition ID: $DefinitionId in project '$Project' (Organization: $Organization)$dateRangeInfo - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}

<#
.SYNOPSIS
    Gets builds matching a specific build number.

.DESCRIPTION
    Retrieves builds that match the given build number string, optionally scoped to a
    specific definition ID, using the Azure DevOps Builds API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER BuildNumber
    Build number string to search for

.PARAMETER DefinitionId
    Optional build definition ID to narrow the search

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $builds = Get-BuildsByBuildNumber -Organization "contoso" -Project "MyProject" -BuildNumber "20260101.1"
#>
function Get-BuildsByBuildNumber {
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
        [string]$BuildNumber,

        [Parameter(Mandatory = $false)]
        [int]$DefinitionId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting builds for build number: $BuildNumber"

        $apiPath = "build/builds?buildNumber=$BuildNumber"

        if ($DefinitionId) {
            $apiPath += "&definitions=$DefinitionId"
        }

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if ($response.value) {
            Write-Host "Found $($response.value.Count) build(s)"

            $builds = @()
            foreach ($build in $response.value) {
                $builds += @{
                    Id = $build.id
                    BuildNumber = $build.buildNumber
                    DefinitionId = $build.definition.id
                    Status = $build.status
                    Result = $build.result
                    SourceVersion = $build.sourceVersion
                    QueueTime = $build.queueTime
                    StartTime = $build.startTime
                    FinishTime = $build.finishTime
                    SourceBranch = $build.sourceBranch
                }
            }

            return $builds
        }
        else {
            Write-Warning "No builds found"
            return @()
        }
    }
    catch {
        $errorMessage = "Failed to get builds for build number: $BuildNumber in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}


<#
.SYNOPSIS
    Gets a specific build by its ID.

.DESCRIPTION
    Retrieves detailed information about a single build including its status, result,
    definition, source branch, and timing information using the Azure DevOps Builds API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER BuildId
    Build ID to retrieve

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $build = Get-Build -Organization "contoso" -Project "MyProject" -BuildId 456
#>
function Get-Build {
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
        [string]$BuildId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting build ID: $BuildId"
        $apiPath = "build/builds/$BuildId"
        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        return @{
            Id = $response.id
            BuildNumber = $response.buildNumber
            Status = $response.status
            Result = $response.result
            QueueTime = $response.queueTime
            StartTime = $response.startTime
            FinishTime = $response.finishTime
            Definition = @{
                Name = $response.definition.name
                Id = $response.definition.id
            }
            SourceBranch = $response.sourceBranch
            SourceVersion = $response.sourceVersion
            Url = $response._links.web.href
        }
    }
    catch {
        $errorMessage = "Failed to get build ID: $BuildId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw
    }
}

<#
.SYNOPSIS
    Gets a specific build artifact by build ID and artifact name.

.DESCRIPTION
    Retrieves detailed information about a single build artifact using the Azure DevOps Builds API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER BuildId
    Build ID to retrieve

.PARAMETER BuildArtifactName
    Artifact Name to retrieve

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $artifact = Get-BuildArtifact -Organization "contoso" -Project "MyProject" -BuildId 456 -BuildArtifactName MyArtifact
#>
function Get-BuildArtifact {
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
        [string]$BuildId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BuildArtifactName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        Write-Host "Getting artifact '$BuildArtifactName' from build ID: $BuildId"
        $apiPath = "build/builds/$BuildId/artifacts?api-version=7.1"
        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if ($response.count -eq 0) {
            $errorMessage = "Failed to find any artifacts."
            Write-Error $errorMessage
            throw $errorMessage
        }

        Write-Host "Found $($response.count) artifact(s)."
        $artifact = $response.value | Where-Object { $_.name -eq $BuildArtifactName }

        # Example artifact object:
        #{
        #    "id": {ID},
        #    "name": "MyArtifactPROD",
        #    "source": "{GUID}",
        #    "resource": {
        #        "type": "PipelineArtifact",
        #        "data": "{DATA}",
        #        "properties": {
        #        "RootId": "{ROOTID}",
        #        "artifactsize": "20781645",
        #        "HashType": "DEDUPNODEORCHUNK",
        #        "DomainId": "0"
        #        },
        #    "url": "{URL}",
        #    "downloadUrl": "{DOWNLOADURL}"
        #}
        return $artifact[0]
    }
    catch {
        $errorMessage = "Failed to get artifact '$BuildArtifactName' from build ID: $BuildId in project '$Project' (Organization: $Organization) - Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw $errorMessage
    }
}

Export-ModuleMember -Function Get-LatestSuccessfulBuild, Get-LatestSuccessfulBuilds, Get-BuildCommits, Get-BuildWorkItems, Get-BuildDefinition, Get-BuildsByDateRange, Get-BuildsByBuildNumber, Get-Build, Get-BuildArtifact
