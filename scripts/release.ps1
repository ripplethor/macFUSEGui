param(
    [ValidateSet("arm64", "x86_64", "both", "universal")]
    [string]$Arch = "both",

    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",

    [string]$ReleaseVersion = "",

    [switch]$DryRun,

    [switch]$SkipBuild,

    [ValidateSet("NO", "YES")]
    [string]$CodeSigningAllowed = "NO",

    [switch]$NoHomebrewCask,

    [switch]$StripDmgPayload,

    [ValidateSet("1", "2", "3", "4", "5", "6", "7", "8", "9")]
    [string]$DmgZlibLevel = "9",

    [switch]$NoWatch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Missing required command '$Name'. Install it, then rerun this script."
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

function Invoke-CaptureChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')`n$message"
    }
    return $output
}

function ConvertTo-GitHubRepoName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteUrl
    )

    $trimmed = $RemoteUrl.Trim()
    $patterns = @(
        '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$',
        '^git@github\.com:(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$',
        '^ssh://git@github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
    )

    foreach ($pattern in $patterns) {
        if ($trimmed -match $pattern) {
            return "$($Matches.owner)/$($Matches.repo)"
        }
    }

    throw "Remote origin is not a supported GitHub URL: $RemoteUrl"
}

function ConvertTo-LowerBool {
    param([bool]$Value)
    if ($Value) {
        return "true"
    }
    return "false"
}

Require-Command git
Require-Command gh

$repoRoot = (Invoke-CaptureChecked git @("rev-parse", "--show-toplevel") | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "Not inside a git repository."
}

Push-Location $repoRoot

try {
    $insideWorkTree = (Invoke-CaptureChecked git @("rev-parse", "--is-inside-work-tree") | Select-Object -First 1).Trim()
    if ($insideWorkTree -ne "true") {
        throw "Not inside a git work tree."
    }

    $branch = (Invoke-CaptureChecked git @("branch", "--show-current") | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Detached HEAD is not supported for release."
    }

    $status = @(Invoke-CaptureChecked git @("status", "--porcelain", "--untracked-files=normal"))
    if ($status.Count -gt 0) {
        throw "Working tree is not clean. Commit or stash changes before releasing."
    }

    $originUrl = (Invoke-CaptureChecked git @("remote", "get-url", "origin") | Select-Object -First 1).Trim()
    $repoName = ConvertTo-GitHubRepoName -RemoteUrl $originUrl

    Write-Host "Repo root: $repoRoot"
    Write-Host "GitHub repo: $repoName"
    Write-Host "Branch: $branch"
    Write-Host ""

    Write-Host "Checking GitHub remote reachability..."
    Invoke-Checked git @("ls-remote", "--exit-code", "origin", "HEAD")

    Write-Host "Checking GitHub CLI authentication..."
    Invoke-Checked gh @("auth", "status", "--hostname", "github.com")

    Write-Host "Checking GitHub repository access..."
    $repoJson = Invoke-CaptureChecked gh @("repo", "view", $repoName, "--json", "nameWithOwner,defaultBranchRef")
    $repoInfo = $repoJson | ConvertFrom-Json
    $defaultBranch = $repoInfo.defaultBranchRef.name
    Write-Host "Default branch: $defaultBranch"

    Write-Host "Fetching origin..."
    Invoke-Checked git @("fetch", "origin")

    Write-Host "Pushing current branch to origin..."
    Invoke-Checked git @("push", "origin", $branch)

    Write-Host "Checking release workflow is available on GitHub..."
    try {
        Invoke-Checked gh @("workflow", "view", "release-macos.yml", "--repo", $repoName)
    }
    catch {
        throw "GitHub cannot see .github/workflows/release-macos.yml yet. Commit this workflow and push it to the repository default branch first."
    }

    $dryRunValue = ConvertTo-LowerBool -Value $DryRun.IsPresent
    $skipBuildValue = ConvertTo-LowerBool -Value $SkipBuild.IsPresent
    $updateCaskValue = ConvertTo-LowerBool -Value (-not $NoHomebrewCask.IsPresent)
    $stripPayloadValue = ConvertTo-LowerBool -Value $StripDmgPayload.IsPresent

    $workflowArgs = @(
        "workflow", "run", "release-macos.yml",
        "--repo", $repoName,
        "--ref", $branch,
        "-f", "arch=$Arch",
        "-f", "configuration=$Configuration",
        "-f", "dry_run=$dryRunValue",
        "-f", "skip_build=$skipBuildValue",
        "-f", "code_signing_allowed=$CodeSigningAllowed",
        "-f", "update_homebrew_cask=$updateCaskValue",
        "-f", "strip_dmg_payload=$stripPayloadValue",
        "-f", "dmg_zlib_level=$DmgZlibLevel"
    )

    if (-not [string]::IsNullOrWhiteSpace($ReleaseVersion)) {
        $workflowArgs += @("-f", "release_version=$ReleaseVersion")
    }

    Write-Host ""
    Write-Host "Triggering macOS release workflow..."
    Invoke-Checked gh $workflowArgs

    Start-Sleep -Seconds 8

    $runJson = Invoke-CaptureChecked gh @(
        "run", "list",
        "--repo", $repoName,
        "--workflow", "release-macos.yml",
        "--branch", $branch,
        "--event", "workflow_dispatch",
        "--limit", "1",
        "--json", "databaseId,status,conclusion,url,createdAt,displayTitle"
    )

    $runs = @($runJson | ConvertFrom-Json)
    if ($runs.Count -eq 0) {
        throw "Workflow was triggered, but no matching run could be found."
    }

    $run = $runs[0]
    Write-Host ""
    Write-Host "GitHub Actions run:"
    Write-Host $run.url
    Write-Host ""

    if (-not $NoWatch.IsPresent) {
        Write-Host "Watching release workflow..."
        Invoke-Checked gh @("run", "watch", "$($run.databaseId)", "--repo", $repoName, "--exit-status")
    }
}
finally {
    Pop-Location
}
