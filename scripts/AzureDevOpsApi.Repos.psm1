# AzureDevOpsApi.Repos.psm1
# Repository file operations for Azure DevOps Git

<#
.SYNOPSIS
    Downloads files from a directory in an Azure DevOps Git repository.

.DESCRIPTION
    Uses the Git Items API to list files in a repository directory, then downloads
    each file to a local directory preserving the folder structure.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER Path
    Repository directory path to download (e.g., "/config/18.x")

.PARAMETER OutputDirectory
    Local directory to download files to

.PARAMETER Branch
    Branch name to read from (default: "main")

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $result = Get-RepoFiles -Organization "contoso" -Project "MyProject" -Repository "MyTools" `
        -Path "/config/18.x" -OutputDirectory "$env:TEMP\config" -Branch "master"

.EXAMPLE
    $result = Get-RepoFiles -Organization "contoso" -Project "MyProject" -Repository "MyRepo" `
        -Path "/config/packages/common" -OutputDirectory "C:\pkgsets"
#>
function Get-RepoFiles {
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
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $false)]
        [string]$Branch = "main",

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    # Strip refs/heads/ prefix if present (e.g. from Build.SourceBranch)
    $Branch = $Branch -replace '^refs/heads/', ''

    try {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

        # List all files in the directory tree
        $listApiPath = "git/repositories/$Repository/items?scopePath=$Path&recursionLevel=full&download=false&versionDescriptor.version=$Branch&versionDescriptor.versionType=branch"

        Write-Host "Listing files in $Organization/$Project/$Repository : $Path (branch: $Branch)..."

        $items = Invoke-AzureDevOpsApi `
            -Organization $Organization `
            -Project $Project `
            -ApiPath $listApiPath `
            -AccessToken $AccessToken `
            -AuthenticationType $AuthenticationType

        $files = @($items.value | Where-Object { -not $_.isFolder })

        if ($files.Count -eq 0) {
            Write-Warning "No files found at path $Path in $Repository (branch: $Branch)"
            return @{
                Success   = $false
                Path      = $Path
                FileCount = 0
                Files     = @()
            }
        }

        Write-Host "Found $($files.Count) files — downloading..."

        $downloadedFiles = @()
        foreach ($file in $files) {
            $repoPath = $file.path
            $localPath = Join-Path $OutputDirectory $repoPath.TrimStart('/')
            $localDir = Split-Path $localPath
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null

            $downloadApiPath = "git/repositories/$Repository/items?path=$repoPath&download=true&versionDescriptor.version=$Branch&versionDescriptor.versionType=branch"

            Invoke-AzureDevOpsApi `
                -Organization $Organization `
                -Project $Project `
                -ApiPath $downloadApiPath `
                -AccessToken $AccessToken `
                -AuthenticationType $AuthenticationType `
                -OutFile $localPath

            $downloadedFiles += $repoPath
            Write-Host "  $repoPath"
        }

        Write-Host "Downloaded $($downloadedFiles.Count) files to $OutputDirectory" -ForegroundColor Green

        return @{
            Success   = $true
            Path      = $Path
            FileCount = $downloadedFiles.Count
            Files     = $downloadedFiles
        }
    }
    catch {
        Write-Error "Failed to download files from $Organization/$Project/$Repository $Path : $_"
        throw
    }
}

<#
.SYNOPSIS
    Gets the content of a single file from an Azure DevOps Git repository.

.DESCRIPTION
    Downloads a single file from a Git repository and returns its content as a string,
    or saves it to a local file path.

.PARAMETER Organization
    Azure DevOps organization name

.PARAMETER Project
    Project name

.PARAMETER Repository
    Repository name or ID

.PARAMETER Path
    File path in the repository (e.g., "/config/versions.json")

.PARAMETER Branch
    Branch name to read from (default: "main")

.PARAMETER OutFile
    Optional local file path to save to. If not specified, returns content as string.

.PARAMETER AccessToken
    Access token for authentication

.PARAMETER AuthenticationType
    Authentication type: "Bearer" (default) or "Basic"

.EXAMPLE
    $content = Get-RepoFileContent -Organization "contoso" -Project "MyProject" -Repository "MyRepo" `
        -Path "/config/packages/common.packageset" -Branch "release/validation"

.EXAMPLE
    Get-RepoFileContent -Organization "contoso" -Project "MyProject" -Repository "MyTools" `
        -Path "/versions.json" -OutFile "$env:TEMP\versions.json"
#>
function Get-RepoFileContent {
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
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$Branch = "main",

        [Parameter(Mandatory = $false)]
        [string]$OutFile,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Bearer", "Basic")]
        [string]$AuthenticationType = "Bearer"
    )

    $ErrorActionPreference = "Stop"

    # Strip refs/heads/ prefix if present (e.g. from Build.SourceBranch)
    $Branch = $Branch -replace '^refs/heads/', ''

    try {
        $apiPath = "git/repositories/$Repository/items?path=$Path&download=true&versionDescriptor.version=$Branch&versionDescriptor.versionType=branch"

        Write-Host "Getting file $Path from $Repository (branch: $Branch)..."

        if ($OutFile) {
            $dir = Split-Path $OutFile
            if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

            Invoke-AzureDevOpsApi `
                -Organization $Organization `
                -Project $Project `
                -ApiPath $apiPath `
                -AccessToken $AccessToken `
                -AuthenticationType $AuthenticationType `
                -OutFile $OutFile

            Write-Host "Saved to $OutFile" -ForegroundColor Green
            return $OutFile
        }
        else {
            $response = Invoke-AzureDevOpsApi `
                -Organization $Organization `
                -Project $Project `
                -ApiPath $apiPath `
                -AccessToken $AccessToken `
                -AuthenticationType $AuthenticationType

            return $response
        }
    }
    catch {
        Write-Error "Failed to get file $Path from $Repository : $_"
        throw
    }
}

Export-ModuleMember -Function Get-RepoFiles, Get-RepoFileContent
