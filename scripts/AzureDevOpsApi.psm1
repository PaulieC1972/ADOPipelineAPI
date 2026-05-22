# Central PowerShell module for Azure DevOps REST API operations
# This module imports specialized sub-modules organized by functionality area
# AzureDevOpsApi.psm1
# If you update this file, ensure to update the associated manifest by running:
# powershell New-ModuleManifest -Path ./AzureDevOpsApi.psd1 -RootModule AzureDevOpsApi.psm1
# and include both in your pull request

# Get the module directory
$moduleRoot = $PSScriptRoot

# Import Core module (required by all other modules)
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.Core.psm1") -Force

# Import specialized modules
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.Builds.psm1") -Force
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.Commits.psm1") -Force
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.PullRequests.psm1") -Force
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.Branches.psm1") -Force
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.Tags.psm1") -Force
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.Packages.psm1") -Force
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.Repos.psm1") -Force
Import-Module (Join-Path $moduleRoot "AzureDevOpsApi.Pipelines.psm1") -Force

# Export all functions from the imported modules
Export-ModuleMember -Function @(
    # Core
    'Invoke-AzureDevOpsApi',
    'Set-PipelineVariable',
    # Builds
    'Get-LatestSuccessfulBuild',
    'Get-LatestSuccessfulBuilds',
    'Get-BuildCommits',
    'Get-BuildWorkItems',
    'Get-BuildDefinition',
    'Get-BuildsByBuildNumber',
    'Get-BuildsByDateRange',
    'Get-Build',
    'Get-BuildArtifact',
    # Commits
    'Get-Commit',
    'Compare-Branches',
    'New-Commit',
    'Test-CommitAncestry',
    # Pull Requests
    'Get-PullRequest',
    'New-PullRequest',
    'Set-PullRequestAutoComplete',
    'Set-PullRequestVote',
    # Branches
    'Get-Branch',
    'Get-Branches',
    'New-Branch',
    'Remove-Branch',
    # Tags
    'Get-Tag',
    'Get-BuildTag',
    'Get-Tags',
    'New-Tag',
    'New-BuildTag',
    'Remove-Tag',
    'Remove-BuildTag',
    # Packages
    'Test-NuGetPackageExists',
    'Update-PackagesetVersion',
    'Get-PackagesetVersion',
    # Repos
    'Get-RepoFiles',
    'Get-RepoFileContent',
    # Pipelines
    'Invoke-PipelineRun',
    'Get-PipelineRunStatus',
    'Wait-PipelineRun',
    'Stop-Build'
)
