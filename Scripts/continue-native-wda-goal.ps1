param(
    [string]$Repo = "gpt0609/0511_Appium_WDA",
    [string]$Workflow = "native-wda-host.yml",
    [string]$Ref = "main",
    [string]$RunnerLabel = "macos-14",
    [string]$XcodeVersion = "latest-stable",
    [string]$TokenPath = "Github.txt",
    [string]$ArtifactName = "LobsterWDAHost-unsigned-ipa",
    [string]$OutputDirectory = "artifacts\lobster-wda-host",
    [string]$DeviceUdid = "00008030-0001598021E2802E",
    [string]$BundleId = "app.honey4212.crystal5671",
    [string]$IPhoneHost = "",
    [int]$PollSeconds = 20,
    [int]$TimeoutMinutes = 60,
    [switch]$SkipDispatch,
    [switch]$SkipInstall,
    [switch]$SkipLaunch,
    [switch]$SkipWirelessCheck
)

$ErrorActionPreference = "Stop"

function Resolve-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Read-GitHubToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = Resolve-File -Path $Path -Label "GitHub token file"
    $token = Get-Content -LiteralPath $resolved |
        Where-Object { $_ -match 'gh[pousr]_' } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "GitHub token not found in: $Path"
    }
    return $token.Trim()
}

function Invoke-GitHubJson {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$Method = "Get",
        [object]$Body = $null
    )

    if ($null -eq $Body) {
        return Invoke-RestMethod -Headers $Headers -Method $Method -Uri $Uri
    }

    return Invoke-RestMethod `
        -Headers $Headers `
        -Method $Method `
        -Uri $Uri `
        -Body ($Body | ConvertTo-Json -Depth 8) `
        -ContentType "application/json"
}

function Get-LatestWorkflowRun {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [string]$Workflow,
        [Parameter(Mandatory = $true)]
        [string]$Ref
    )

    $uri = "https://api.github.com/repos/$Repo/actions/workflows/$Workflow/runs?per_page=10&branch=$Ref&event=workflow_dispatch"
    $runs = Invoke-GitHubJson -Headers $Headers -Uri $uri
    $run = $runs.workflow_runs | Select-Object -First 1
    if ($null -eq $run) {
        throw "No workflow_dispatch runs found for $Workflow on $Ref"
    }
    return $run
}

function Get-RunFailureMessages {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [object]$Jobs
    )

    $messages = New-Object System.Collections.Generic.List[string]
    foreach ($job in $Jobs.jobs) {
        if ([string]::IsNullOrWhiteSpace($job.check_run_url)) {
            continue
        }
        $checkRunId = $job.check_run_url.Split("/")[-1]
        $annotations = Invoke-GitHubJson `
            -Headers $Headers `
            -Uri "https://api.github.com/repos/$Repo/check-runs/$checkRunId/annotations?per_page=100"
        foreach ($annotation in $annotations) {
            if (-not [string]::IsNullOrWhiteSpace($annotation.message)) {
                $messages.Add($annotation.message)
            }
        }
    }
    return $messages
}

function Wait-WorkflowRun {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $true)]
        [int]$PollSeconds,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutMinutes
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        $run = Invoke-GitHubJson `
            -Headers $Headers `
            -Uri "https://api.github.com/repos/$Repo/actions/runs/$RunId"
        $jobs = Invoke-GitHubJson `
            -Headers $Headers `
            -Uri "https://api.github.com/repos/$Repo/actions/runs/$RunId/jobs?per_page=100"

        $jobSummary = $jobs.jobs |
            ForEach-Object { "$($_.name):$($_.status):$($_.conclusion):runner=$($_.runner_name)" }
        Write-Host "Run $RunId status=$($run.status) conclusion=$($run.conclusion) jobs=[$($jobSummary -join '; ')]"

        if ($run.status -eq "completed") {
            if ($run.conclusion -ne "success") {
                $messages = Get-RunFailureMessages -Headers $Headers -Repo $Repo -Jobs $jobs
                if ($messages.Count -gt 0) {
                    throw "Workflow run $RunId failed: $($messages -join ' | ')"
                }
                throw "Workflow run $RunId failed with conclusion: $($run.conclusion)"
            }
            return $run
        }

        Start-Sleep -Seconds $PollSeconds
    }

    throw "Timed out waiting for workflow run $RunId after $TimeoutMinutes minutes"
}

function Download-Artifact {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $true)]
        [string]$ArtifactName,
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    $artifacts = Invoke-GitHubJson `
        -Headers $Headers `
        -Uri "https://api.github.com/repos/$Repo/actions/runs/$RunId/artifacts?per_page=100"
    $artifact = $artifacts.artifacts | Where-Object { $_.name -eq $ArtifactName } | Select-Object -First 1
    if ($null -eq $artifact) {
        $names = $artifacts.artifacts | ForEach-Object { $_.name }
        throw "Artifact not found: $ArtifactName. Available: $($names -join ', ')"
    }

    $resolvedOutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null

    $zipPath = Join-Path $resolvedOutputDirectory "$ArtifactName.zip"
    $extractPath = Join-Path $resolvedOutputDirectory "$ArtifactName-$RunId"
    if (Test-Path -LiteralPath $extractPath) {
        $extractPath = Join-Path $resolvedOutputDirectory "$ArtifactName-$RunId-$(Get-Date -Format yyyyMMddHHmmss)"
    }

    Invoke-WebRequest -Headers $Headers -Uri $artifact.archive_download_url -OutFile $zipPath
    New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $ipa = Get-ChildItem -LiteralPath $extractPath -Filter "*.ipa" -Recurse -File | Select-Object -First 1
    if ($null -eq $ipa) {
        throw "No IPA found in artifact: $ArtifactName"
    }
    return $ipa.FullName
}

function Test-WdaEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $uri = "$BaseUrl$Path"
    $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri $uri
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "$uri returned HTTP $($response.StatusCode)"
    }
    Write-Host "$uri OK ($($response.RawContentLength) bytes)"
}

if ([string]::IsNullOrWhiteSpace($DeviceUdid) -and -not $SkipInstall) {
    throw "DeviceUdid is required unless -SkipInstall is used"
}
if ([string]::IsNullOrWhiteSpace($BundleId) -and -not $SkipLaunch) {
    throw "BundleId is required unless -SkipLaunch is used"
}

$token = Read-GitHubToken -Path $TokenPath
$headers = @{
    Authorization = "Bearer $token"
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "codex-local-wda-build"
}

if (-not $SkipDispatch) {
    $body = @{
        ref = $Ref
        inputs = @{
            xcode_version = $XcodeVersion
            runner_label = $RunnerLabel
        }
    }
    Invoke-GitHubJson `
        -Headers $headers `
        -Method "Post" `
        -Uri "https://api.github.com/repos/$Repo/actions/workflows/$Workflow/dispatches" `
        -Body $body
    Start-Sleep -Seconds 5
}

$run = Get-LatestWorkflowRun -Headers $headers -Repo $Repo -Workflow $Workflow -Ref $Ref
Write-Host "Using workflow run: $($run.id) $($run.html_url)"
$completedRun = Wait-WorkflowRun `
    -Headers $headers `
    -Repo $Repo `
    -RunId $run.id `
    -PollSeconds $PollSeconds `
    -TimeoutMinutes $TimeoutMinutes

$unsignedIpa = Download-Artifact `
    -Headers $headers `
    -Repo $Repo `
    -RunId $completedRun.id `
    -ArtifactName $ArtifactName `
    -OutputDirectory $OutputDirectory
Write-Host "Unsigned IPA: $unsignedIpa"

$signedIpa = Join-Path (Split-Path -Parent $unsignedIpa) "LobsterWDAHost.signed.ipa"
$resignArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    ".\Scripts\resign-native-wda.ps1",
    "-InputIpa",
    $unsignedIpa,
    "-OutputIpa",
    $signedIpa
)
if (-not $SkipInstall) {
    $resignArgs += @("-Install", "-DeviceUdid", $DeviceUdid)
}
& powershell @resignArgs
if ($LASTEXITCODE -ne 0) {
    throw "resign-native-wda.ps1 failed with exit code $LASTEXITCODE"
}

if (-not $SkipInstall -and -not $SkipLaunch) {
    & tidevice -u $DeviceUdid launch $BundleId
    if ($LASTEXITCODE -ne 0) {
        throw "tidevice launch failed with exit code $LASTEXITCODE"
    }
    Start-Sleep -Seconds 3
}

if (-not $SkipWirelessCheck) {
    if ([string]::IsNullOrWhiteSpace($IPhoneHost)) {
        throw "IPhoneHost is required for wireless checks. Re-run with -IPhoneHost <iPhone Wi-Fi IP> or use -SkipWirelessCheck."
    }
    $baseUrl = "http://$IPhoneHost`:8100"
    Test-WdaEndpoint -BaseUrl $baseUrl -Path "/status"
    Test-WdaEndpoint -BaseUrl $baseUrl -Path "/screenshot"
    Test-WdaEndpoint -BaseUrl $baseUrl -Path "/source"
}

Write-Host "LobsterWDAHost chain finished."
