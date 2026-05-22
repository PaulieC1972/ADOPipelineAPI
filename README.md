# ADOPipelineAPI

PowerShell module and Azure DevOps pipeline step templates for interacting with the Azure DevOps REST API.

The module wraps common build, commit, pull request, branch, tag, package, repository, and pipeline operations behind PowerShell cmdlets, and exposes them as reusable YAML step templates for ADO pipelines.

## Repository layout

```
scripts/    PowerShell module (AzureDevOpsApi.psm1 + topic sub-modules)
steps/      Azure DevOps YAML step templates that wrap individual cmdlets
```

## scripts/

A central module (`AzureDevOpsApi.psm1`) loads topic sub-modules and re-exports every public function:

| Sub-module | Functions |
|---|---|
| `AzureDevOpsApi.Core.psm1` | `Invoke-AzureDevOpsApi`, `Set-PipelineVariable` |
| `AzureDevOpsApi.Builds.psm1` | `Get-Build`, `Get-LatestSuccessfulBuild`, `Get-LatestSuccessfulBuilds`, `Get-BuildsByBuildNumber`, `Get-BuildsByDateRange`, `Get-BuildCommits`, `Get-BuildWorkItems`, `Get-BuildDefinition`, `Get-BuildArtifact` |
| `AzureDevOpsApi.Commits.psm1` | `Get-Commit`, `Compare-Branches`, `New-Commit`, `Test-CommitAncestry` |
| `AzureDevOpsApi.PullRequests.psm1` | `Get-PullRequest`, `New-PullRequest`, `Set-PullRequestAutoComplete`, `Set-PullRequestVote` |
| `AzureDevOpsApi.Branches.psm1` | `Get-Branch`, `Get-Branches`, `New-Branch`, `Remove-Branch` |
| `AzureDevOpsApi.Tags.psm1` | `Get-Tag`, `Get-Tags`, `New-Tag`, `Remove-Tag`, `Get-BuildTag`, `New-BuildTag`, `Remove-BuildTag` |
| `AzureDevOpsApi.Packages.psm1` | `Test-NuGetPackageExists`, `Get-PackagesetVersion`, `Update-PackagesetVersion` |
| `AzureDevOpsApi.Repos.psm1` | `Get-RepoFiles`, `Get-RepoFileContent` |
| `AzureDevOpsApi.Pipelines.psm1` | `Invoke-PipelineRun`, `Get-PipelineRunStatus`, `Wait-PipelineRun`, `Stop-Build` |

`Invoke-AzureDevOpsApi` is the underlying HTTP wrapper used by every other cmdlet — it handles Bearer/Basic auth, JSON serialization, exponential-backoff retries, and file downloads. Use it directly to hit endpoints not yet covered by a dedicated cmdlet.

## steps/

Each `*_Step.yml` is a thin wrapper around one cmdlet, designed to be consumed from a pipeline via `- template:`. Steps publish their results back to the pipeline as variables (regular and `isOutput: true`) so downstream jobs can consume them.

| Template | Purpose |
|---|---|
| `GetBuild_Step.yml` | Get a single build by ID |
| `GetBuildByBuildNumber_Step.yml` | Find builds matching a build number |
| `GetBuildByDateRange_Step.yml` | List builds in a date window |
| `GetBuildCommits_Step.yml` | Commits associated with a build |
| `GetBuildDefinition_Step.yml` | Build definition metadata |
| `GetBuildWorkitems_Step.yml` | Work items linked to a build |
| `GetLatestBuild_Step.yml` | Latest successful build for a definition |
| `GetLatestSuccessfulBuilds_Step.yml` | N most recent successful builds |
| `GetCommit_Step.yml` | Commit details for a SHA |
| `CompareBranches_Step.yml` | Commits in target branch not in base branch |
| `GetPullRequest_Step.yml` | Pull request metadata |
| `GetRepoFiles_Step.yml` | Download all files under a repo path |
| `GetRepoFileContent_Step.yml` | Read a single repo file |
| `GetPackagesetVersion_Step.yml` | Read a package's version from a packageset file |
| `InvokePipelineRun_Step.yml` | Queue a pipeline run (optionally wait for completion) |
| `GetPipelineRunStatus_Step.yml` | Poll a pipeline run's state |
| `StopBuild_Step.yml` | Cancel a running build |

## Usage

### Authentication

All cmdlets accept an `-AccessToken` parameter (defaulting to `$env:SYSTEM_ACCESSTOKEN`) and an `-AuthenticationType` of `Bearer` (default) or `Basic`. In an ADO pipeline, expose the system token to the script step:

```yaml
- pwsh: |
    Import-Module /ADOPipelineAPI/scripts/AzureDevOpsApi.psm1
    Get-Build -Organization "contoso" -Project "MyProject" -BuildId 12345
```

### Direct PowerShell use

Clone the repo, add the scripts (and templates, if required) to your project and import the central module:

```powershell
Import-Module ./scripts/AzureDevOpsApi.psm1

$build = Get-LatestSuccessfulBuild `
    -Organization "contoso" `
    -Project "MyProject" `
    -DefinitionId 123 `
    -AccessToken $env:ADO_PAT `
    -AuthenticationType Basic

Write-Host "Latest green build: $($build.BuildNumber) at $($build.SourceVersion)"
```

Personal Access Tokens (PATs) use `-AuthenticationType Basic`. The pipeline `System.AccessToken` uses `Bearer` (the default).

### Consuming step templates from an ADO pipeline

These templates are intended to live **inside your own repository** rather than be referenced from this one. Copy (or vendor) the `scripts/` and `steps/` directories into your repo — for example under `ADOPipelineAPI/scripts/` and `ADOPipelineAPI/steps/` — so the `Import-Module` path baked into each step (`/ADOPipelineAPI/scripts/AzureDevOpsApi.psm1`) resolves against your checked-out sources.

Pulling them into your repo lets you:

- Pin a known-good revision and update on your own schedule.
- Patch or extend cmdlets locally without depending on an external service connection.
- Avoid configuring a GitHub service endpoint just to fetch templates at queue time.

A typical layout in your repo:

```
<your-repo>/
├── pipelines/
│   └── azure-pipelines.yml
└── ADOPipelineAPI/
    ├── scripts/
    │   ├── AzureDevOpsApi.psm1
    │   └── AzureDevOpsApi.*.psm1
    └── steps/
        └── *_Step.yml
```

Then reference a step template directly from `self`:

```yaml
steps:
  - checkout: self

  - template: /ADOPipelineAPI/steps/GetLatestBuild_Step.yml
    parameters:
      organization: contoso
      project: MyProject
      definitionId: 123
      stepName: latestBuild

  - pwsh: |
      Write-Host "Build number: $(latestBuild.BuildNumber)"
      Write-Host "Source SHA:   $(latestBuild.SourceVersion)"
```

If your pipeline source repository uses a different root path, adjust either the `path:` on the `checkout` step or the `Import-Module` line inside each `*_Step.yml` so the module is found at `/ADOPipelineAPI/scripts/AzureDevOpsApi.psm1`.

Each step writes its outputs as pipeline variables prefixed by the `stepName` parameter (and also as plain variables for same-stage consumption). Inspect the individual `*_Step.yml` for the exact variable names a template publishes.

### Chaining steps

The output variables make step templates composable. For example, find the latest successful build, then list its commits:

```yaml
- template: /ADOPipelineAPI/steps/GetLatestBuild_Step.yml
  parameters:
    organization: contoso
    project: MyProject
    definitionId: 123
    stepName: latest

- template: /ADOPipelineAPI/steps/GetBuildCommits_Step.yml
  parameters:
    organization: contoso
    project: MyProject
    buildId: $(latest.BuildId)
    stepName: commits
```

## Extending

To add a new cmdlet:

1. Pick or add the appropriate `AzureDevOpsApi.<Topic>.psm1` and write a function that calls `Invoke-AzureDevOpsApi`.
2. Append the function name to the relevant `Export-ModuleMember` list inside that sub-module **and** to the central `Export-ModuleMember` list in `AzureDevOpsApi.psm1`.
3. (Optional) Add a `<Name>_Step.yml` wrapper under `steps/` that imports the central module and publishes the result via `Set-PipelineVariable`.

## Notes

- Default values for `organization`, `project`, and `repository` in the step templates (`contoso`, `MyProject`, `MyRepo`) are placeholders — supply real values when you invoke a template.
- The HTTP wrapper retries transient failures (3 attempts, exponential backoff) by default; tune via `-MaxRetries` and `-RetryDelaySeconds`.
- For NuGet flat container queries, pass `-BaseUrl "https://pkgs.dev.azure.com"` to `Invoke-AzureDevOpsApi`. The Packages cmdlets already do this.
