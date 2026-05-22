# AzureDevOpsApi.Packages.psm1
# NuGet package operations for Azure DevOps Artifacts

<#
.SYNOPSIS
    Tests whether a NuGet package version exists on an Azure DevOps Artifacts feed.

.DESCRIPTION
    Queries the NuGet flat container index API to determine if a specific package
    version is already published to the feed.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER FeedName
    Artifacts feed name

.PARAMETER PackageId
    NuGet package ID

.PARAMETER Version
    Package version to check

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $exists = Test-NuGetPackageExists -Organization "contoso" -Project "MyProject" -FeedName "MyFeed" `
        -PackageId "Contoso.Tools.Common" -Version "1.0.0"
    if ($exists) { Write-Host "Package already published" }
#>
function Test-NuGetPackageExists {
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
        [string]$FeedName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    try {
        $pkgIdLower = $PackageId.ToLower()
        $versionLower = $Version.ToLower()
        $apiPath = "_packaging/$FeedName/nuget/v3/flat2/$pkgIdLower/index.json"

        Write-Host "Checking if $PackageId $Version exists on $FeedName..."

        try {
            $response = Invoke-AzureDevOpsApi `
                -Organization $Organization `
                -Project $Project `
                -ApiPath $apiPath `
                -AccessToken $AccessToken `
                -AuthenticationType $AuthenticationType `
                -BaseUrl "https://pkgs.dev.azure.com"
        }
        catch {
            # Invoke-AzureDevOpsApi wraps the error, so check both the Response object
            # and the error message string for 404
            $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { $null }
            if ($statusCode -eq 404 -or $_.Exception.Message -match 'Status Code: 404' -or $_.Exception.Message -match '404 \(Not Found\)') {
                Write-Host "Package $PackageId not found on $FeedName"
                return $false
            }
            throw
        }

        $exists = $response.versions -contains $versionLower
        Write-Host "Package $PackageId $Version $(if ($exists) { 'EXISTS' } else { 'not found' }) on $FeedName"
        return $exists
    }
    catch {
        Write-Error "Failed to check package existence for $PackageId $Version : $_"
        throw
    }
}

<#

.DESCRIPTION
    Reads a packageset JSON file from a branch and returns the version of the
    specified package. Useful for checking if a version update is needed.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER PackagesetPath
    Repository path to the .packageset file

.PARAMETER PackageId
    NuGet package ID to look up (also matches OldPackageId)

.PARAMETER OldPackageId
    Optional old package ID to also match (for migration scenarios)

.PARAMETER Branch
    Branch to read from (default: "main")

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $info = Get-PackagesetVersion -Organization "contoso" -Project "MyProject" -Repository "MyRepo" `
        -PackagesetPath "config/packages/common.packageset" `
        -PackageId "Contoso.Tools.Common" -OldPackageId "Contoso.Tools.Legacy" `
        -Branch "release/validation"
    Write-Host "Current version: $($info.Version)"
#>
function Get-PackagesetVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$PackagesetPath,

        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [Parameter(Mandatory = $false)]
        [string]$OldPackageId,

        [Parameter(Mandatory = $false)]
        [string]$Branch = "main",

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        $content = Get-RepoFileContent -Organization $Organization -Project $Project `
            -Repository $Repository -Path "/$PackagesetPath" -Branch $Branch `
            -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        # Invoke-RestMethod may auto-parse JSON into an object — handle both cases
        if ($content -is [string]) {
            $packageset = $content | ConvertFrom-Json -ErrorAction Stop
        } else {
            $packageset = $content
        }

        $matchIds = @($PackageId)
        if ($OldPackageId) { $matchIds += $OldPackageId }
        $pkg = $packageset.packages.nuget | Where-Object { $_.id -in $matchIds }

        if (-not $pkg) {
            throw "Package $($matchIds -join ' / ') not found in $PackagesetPath"
        }

        return @{
            Success   = $true
            PackageId = $pkg.id
            Version   = $pkg.version
        }
    }
    catch {
        Write-Error "Failed to get packageset version: $_"
        throw
    }
}

<#
.SYNOPSIS
    Updates a package version in a packageset file via Git commit.

.DESCRIPTION
    Reads a packageset JSON file from a branch, updates the specified package's
    version (and optionally renames its ID), then commits the change. Commonly used
    to bump NuGet package versions in packageset files.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER BranchName
    Branch to commit the change to (without refs/heads/ prefix)

.PARAMETER PackagesetPath
    Repository path to the .packageset file

.PARAMETER PackageId
    NuGet package ID to update (also matches old ID for migration)

.PARAMETER OldPackageId
    Optional old package ID to match and rename (for package ID migration)

.PARAMETER NewVersion
    New version to set

.PARAMETER AuthorName
    Author name for the commit

.PARAMETER AuthorEmail
    Author email for the commit

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    Update-PackagesetVersion -Organization "contoso" -Project "MyProject" -Repository "MyRepo" `
        -BranchName "feature/release/1.0.0" `
        -PackagesetPath "config/packages/common.packageset" `
        -PackageId "Contoso.Tools.Common" -OldPackageId "Contoso.Tools.Legacy" `
        -NewVersion "1.0.0" `
        -AuthorName "CI Pipeline" -AuthorEmail "ci@example.com"
#>
function Update-PackagesetVersion {
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
        [string]$PackagesetPath,

        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [Parameter(Mandatory = $false)]
        [string]$OldPackageId,

        [Parameter(Mandatory = $true)]
        [string]$NewVersion,

        [Parameter(Mandatory = $true)]
        [string]$AuthorName,

        [Parameter(Mandatory = $true)]
        [string]$AuthorEmail,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    try {
        # Read current packageset
        Write-Host "Reading packageset from $BranchName : $PackagesetPath"
        $content = Get-RepoFileContent -Organization $Organization -Project $Project `
            -Repository $Repository -Path "/$PackagesetPath" -Branch $BranchName `
            -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        if ($content -is [string]) {
            $packageset = $content | ConvertFrom-Json -ErrorAction Stop
        } else {
            $packageset = $content
        }

        # Find the package entry (match current or old ID)
        $matchIds = @($PackageId)
        if ($OldPackageId) { $matchIds += $OldPackageId }
        $pkg = $packageset.packages.nuget | Where-Object { $_.id -in $matchIds }

        if (-not $pkg) {
            throw "Package entry $($matchIds -join ' / ') not found in $PackagesetPath"
        }

        # Migrate package ID if needed
        if ($OldPackageId -and $pkg.id -eq $OldPackageId) {
            Write-Host "Migrating package id: $OldPackageId → $PackageId"
            $pkg.id = $PackageId
        }

        $oldVersion = $pkg.version
        $pkg.version = $NewVersion
        $updatedContent = $packageset | ConvertTo-Json -Depth 5

        Write-Host "Updating $PackageId : $oldVersion → $NewVersion"

        # Commit the change
        $result = New-Commit -Organization $Organization -Project $Project `
            -Repository $Repository -BranchName $BranchName `
            -FilePath $PackagesetPath `
            -FileContent $updatedContent `
            -CommitMessage "Update $PackageId to $NewVersion" `
            -AuthorName $AuthorName -AuthorEmail $AuthorEmail `
            -AccessToken $AccessToken -AuthenticationType $AuthenticationType

        Write-Host "Packageset updated successfully (commit: $($result.CommitId))" -ForegroundColor Green

        return @{
            Success    = $true
            CommitId   = $result.CommitId
            OldVersion = $oldVersion
            NewVersion = $NewVersion
        }
    }
    catch {
        Write-Error "Failed to update packageset: $_"
        throw
    }
}

Export-ModuleMember -Function Test-NuGetPackageExists, Update-PackagesetVersion, Get-PackagesetVersion
