# AzureDevOpsApi.Tags.psm1
# Tag-related functions for Azure DevOps

<#
.SYNOPSIS
    Gets information about a specific tag in an Azure DevOps repository.

.DESCRIPTION
    Retrieves tag details including object ID and resolved commit ID. For annotated tags,
    resolves the tag object to the underlying commit using the Annotated Tags API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER TagName
    Tag name to look up (without refs/tags/ prefix)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $tag = Get-Tag -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -TagName "v1.0.0"
#>
function Get-Tag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $apiPath = "git/repositories/$Repository/refs?filter=tags/$TagName"
        Write-Host "Getting tag information for: $TagName"

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        # Filter for exact match since the API does prefix matching
        $exactMatch = $response.value | Where-Object { $_.name -eq "refs/tags/$TagName" }

        if ($exactMatch) {
            # The refs API returns the tag object ID for annotated tags, not the commit ID.
            # Use the annotated tags API to resolve the actual commit ID.
            $peeledObjectId = $null
            $commitId = $exactMatch.objectId
            try {
                $tagDetailPath = "git/repositories/$Repository/annotatedtags/$($exactMatch.objectId)"
                $tagDetail = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $tagDetailPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"
                if ($tagDetail -and $tagDetail.taggedObject -and $tagDetail.taggedObject.objectId) {
                    $peeledObjectId = $tagDetail.taggedObject.objectId
                    $commitId = $peeledObjectId
                    Write-Host "Resolved annotated tag object $($exactMatch.objectId) to commit $commitId"
                }
            }
            catch {
                # Not an annotated tag (lightweight tag) — objectId is already the commit ID
                Write-Host "Tag is lightweight, objectId is the commit ID"
            }

            Write-Host "Found tag: $($exactMatch.name) -> ObjectId: $($exactMatch.objectId), CommitId: $commitId" -ForegroundColor Green
            return @{
                Success        = $true
                Name           = $exactMatch.name
                ObjectId       = $exactMatch.objectId
                PeeledObjectId = $peeledObjectId
                CommitId       = $commitId
                Url            = $exactMatch.url
            }
        }
        else {
            Write-Host "Tag '$TagName' not found"
            return @{
                Success = $false
                Name    = $TagName
            }
        }
    }
    catch {
        Write-Error "Error getting tag information: $_"
        throw
    }
}

<#
.SYNOPSIS
    Gets information about a specific build tag in Azure DevOps.

.DESCRIPTION
    Retrieves a single build tag's information from Azure DevOps.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER DefinitionId
    Build definition ID to query

.PARAMETER TagName
    Tag name

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    Get-BuildTag -Organization "contoso" -Project "MyProject" -TagName "prod" -AccessToken $token
#>
function Get-BuildTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $apiPath = "build/builds?definitions=$DefinitionId&tagFilters=$TagName"
        Write-Host "Getting build tag information for: $TagName"

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        $exactMatch = $response.value | Where-Object { "$TagName" -in $_.tags }

        if ($exactMatch) {
            Write-Host "Found tag on build(s): $($exactMatch.id)" -ForegroundColor Green

            return @{
                Success = $true
                Name    = $TagName
                Builds  = $exactMatch
            }
        }
        else {
            Write-Host "Tag '$TagName' not found"
            return @{
                Success = $false
                Name    = $TagName
            }
        }
    }
    catch {
        Write-Error "Error getting build tag information: $_"
        throw
    }
}


<#
.SYNOPSIS
    Gets a list of tags in an Azure DevOps repository.

.DESCRIPTION
    Retrieves all tags or tags matching a filter from the specified Azure DevOps repository
    using the Git Refs API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER Filter
    Optional filter string to match tag names

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = Get-Tags -Organization "contoso" -Project "MyProject" -Repository "MyRepo"

.EXAMPLE
    $result = Get-Tags -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -Filter "v1."
#>
function Get-Tags {
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
            $apiPath = "git/repositories/$Repository/refs?filter=tags/$Filter"
            Write-Host "Getting tags matching filter: $Filter"
        }
        else {
            $apiPath = "git/repositories/$Repository/refs?filter=tags/"
            Write-Host "Getting all tags"
        }

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($response.value -and $response.value.Count -gt 0) {
            Write-Host "Found $($response.value.Count) tag(s)" -ForegroundColor Green
            return @{
                Success = $true
                Count   = $response.value.Count
                Tags    = $response.value
            }
        }
        else {
            $filterMsg = if ($Filter) { " matching filter '$Filter'" } else { "" }
            Write-Warning "No tags found$filterMsg"
            return @{
                Success = $false
                Count   = 0
                Tags    = @()
            }
        }
    }
    catch {
        Write-Error "Error getting tags: $_"
        throw
    }
}


<#
.SYNOPSIS
    Creates a new tag in an Azure DevOps repository.

.DESCRIPTION
    Creates a lightweight tag pointing to the specified commit using the Azure DevOps
    Git Refs API.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER TagName
    Name of the new tag to create (without refs/tags/ prefix)

.PARAMETER CommitId
    Full SHA of the commit the tag should point to

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = New-Tag -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -TagName "v1.0.0" -CommitId "abc123"
#>
function New-Tag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $true)]
        [string]$CommitId,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $apiPath = "git/repositories/$Repository/refs"
        $tagRef = "refs/tags/$TagName"

        $body = @(
            @{
                name        = $tagRef
                oldObjectId = "0000000000000000000000000000000000000000"
                newObjectId = $CommitId
            }
        )

        Write-Host "Creating tag: $TagName -> $CommitId"

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method POST -Body $body -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($response.value -and $response.value[0].success) {
            Write-Host "Successfully created tag: $TagName" -ForegroundColor Green
            return @{
                Success  = $true
                TagName  = $TagName
                TagRef   = $tagRef
                CommitId = $CommitId
            }
        }
        else {
            $status = if ($response.value) { $response.value[0].updateStatus } else { "unknown" }
            throw "Failed to create tag '$TagName'. Status: $status. Response: $($response | ConvertTo-Json -Depth 10)"
        }
    }
    catch {
        Write-Error "Error creating tag: $_"
        throw
    }
}

<#
.SYNOPSIS
    Creates a lightweight tag on an Azure DevOps build using the REST API.

.DESCRIPTION
    Creates a new tag pointing at the specified build.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER Build
    Build ID

.PARAMETER TagName
    Name of the tag to create

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    New-BuildTag -Organization "contoso" -Project "MyProject" -Build "12345" -TagName "prod" -AccessToken $token
#>
function New-BuildTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Build,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $apiPath = "build/builds/$Build/tags/$TagName"

        Write-Host "Creating build tag: $TagName -> $Build"

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method PUT -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($response.value -and $response.value.count -gt 0) {
            Write-Host "Successfully created build tag: $TagName" -ForegroundColor Green
            return @{
                Success = $true
                TagName = $TagName
                Build   = $Build
            }
        }
        else {
            $status = if ($response.value) { $response.value[0].updateStatus } else { "unknown" }
            throw "Failed to create build tag '$TagName'. Status: $status. Response: $($response | ConvertTo-Json -Depth 10)"
        }
    }
    catch {
        Write-Error "Error creating build tag: $_"
        throw
    }
}


<#
.SYNOPSIS
    Deletes a tag from an Azure DevOps repository.

.DESCRIPTION
    Removes an existing tag by first looking up its current object ID, then deleting
    the ref using the Azure DevOps Git Refs API. No-ops if the tag does not exist.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "contoso")

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER TagName
    Name of the tag to delete (without refs/tags/ prefix)

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to $env:SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = Remove-Tag -Organization "contoso" -Project "MyProject" -Repository "MyRepo" -TagName "v1.0.0"
#>
function Remove-Tag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        # First get the current tag to find its objectId
        $existingTag = Get-Tag -Organization $Organization -Project $Project -Repository $Repository -TagName $TagName -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if (-not $existingTag.Success) {
            Write-Warning "Tag '$TagName' does not exist, nothing to delete"
            return @{
                Success = $true
                TagName = $TagName
                Message = "Tag did not exist"
            }
        }

        $apiPath = "git/repositories/$Repository/refs"
        $tagRef = "refs/tags/$TagName"

        $body = @(
            @{
                name        = $tagRef
                oldObjectId = $existingTag.ObjectId
                newObjectId = "0000000000000000000000000000000000000000"
            }
        )

        Write-Host "Deleting tag: $TagName (was at $($existingTag.ObjectId))"

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method POST -Body $body -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($response.value -and $response.value[0].success) {
            Write-Host "Successfully deleted tag: $TagName" -ForegroundColor Green
            return @{
                Success       = $true
                TagName       = $TagName
                OldObjectId   = $existingTag.ObjectId
            }
        }
        else {
            $status = if ($response.value) { $response.value[0].updateStatus } else { "unknown" }
            throw "Failed to delete tag '$TagName'. Status: $status. Response: $($response | ConvertTo-Json -Depth 10)"
        }
    }
    catch {
        Write-Error "Error deleting tag: $_"
        throw
    }
}

<#
.SYNOPSIS
    Removes a tag from an Azure DevOps build using the REST API.

.DESCRIPTION
    Removes a tag pointing at the specified build.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER Build
    Build ID

.PARAMETER TagName
    Name of the tag to remove

.PARAMETER AccessToken
    Personal Access Token for authentication (defaults to SYSTEM_ACCESSTOKEN)

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    Remove-BuildTag -Organization "contoso" -Project "MyProject" -Build "12345" -TagName "prod" -AccessToken $token
#>
function Remove-BuildTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Build,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $apiPath = "build/builds/$Build/tags/$TagName"

        Write-Host "Removing build tag: $TagName -> $Build"

        $response = Invoke-AzureDevOpsApi -Organization $Organization -Project $Project -ApiPath $apiPath -Method DELETE -AccessToken $AccessToken -AuthenticationType $AuthenticationType -ApiVersion "7.1"

        if ($response.value) {
            Write-Host "Successfully removed build tag: $TagName" -ForegroundColor Green
            return @{
                Success = $true
                TagName = $TagName
                Build   = $Build
            }
        }
        else {
            $status = if ($response.value) { $response.value[0].updateStatus } else { "unknown" }
            throw "Failed to remove build tag '$TagName'. Status: $status. Response: $($response | ConvertTo-Json -Depth 10)"
        }
    }
    catch {
        Write-Error "Error removing build tag: $_"
        throw
    }
}

Export-ModuleMember -Function Get-Tag, Get-BuildTag, Get-Tags, New-Tag, New-BuildTag, Remove-Tag, Remove-BuildTag
