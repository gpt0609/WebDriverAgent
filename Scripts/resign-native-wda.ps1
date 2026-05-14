param(
    [string]$InputIpa = "LobsterWDAHost.unsigned.ipa",
    [string]$OutputIpa = "LobsterWDAHost.signed.ipa",
    [string]$P12Path = "D:\2026_soft\0430_WS\0423_iPhone11\cert.p12",
    [string]$MobileProvisionPath = "D:\2026_soft\0430_WS\0423_iPhone11\cert.mobileprovision",
    [string]$PasswordPath = "D:\2026_soft\0430_WS\0423_iPhone11\password.txt",
    [string]$ZsignPath = ("D:\EC\" + [string][char]0x7B7E + [string][char]0x540D + "\Tool\zsign.exe"),
    [string]$BundleId = "app.honey4212.crystal5671",
    [string]$DisplayName = "Lobster WDA",
    [string]$DeviceUdid = "00008030-0001598021E2802E",
    [switch]$Install
)

$ErrorActionPreference = "Stop"

function Resolve-ExistingFile {
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

function Read-CertificatePassword {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = (Get-Content -LiteralPath $Path -Raw).Trim()
    $content = $content.Trim([char]0xFEFF)
    foreach ($label in @("password", "Password", "P12_PASSWORD", "p12_password")) {
        if ($content.StartsWith($label)) {
            return $content.Substring($label.Length).Trim(" ", "`t", ":", "=")
        }
    }
    $withoutNonAsciiLabel = [regex]::Replace($content, '^[^\x00-\x7F]+[\s\p{P}=]*', '')
    if (-not [string]::IsNullOrWhiteSpace($withoutNonAsciiLabel)) {
        return $withoutNonAsciiLabel
    }
    return $content
}

$resolvedInput = Resolve-ExistingFile -Path $InputIpa -Label "Input IPA"
$resolvedP12 = Resolve-ExistingFile -Path $P12Path -Label "P12 certificate"
$resolvedMobileProvision = Resolve-ExistingFile -Path $MobileProvisionPath -Label "Mobile provisioning profile"
$resolvedPassword = Resolve-ExistingFile -Path $PasswordPath -Label "Password file"
$resolvedZsign = Resolve-ExistingFile -Path $ZsignPath -Label "zsign.exe"
$resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputIpa)
$password = Read-CertificatePassword -Path $resolvedPassword

if ([string]::IsNullOrWhiteSpace($password)) {
    throw "Password file is empty: $PasswordPath"
}

& $resolvedZsign `
    -k $resolvedP12 `
    -m $resolvedMobileProvision `
    -p $password `
    -b $BundleId `
    -n $DisplayName `
    -o $resolvedOutput `
    $resolvedInput

if ($LASTEXITCODE -ne 0) {
    throw "zsign failed with exit code $LASTEXITCODE"
}

Write-Host "Signed IPA: $resolvedOutput"

if ($Install) {
    if ([string]::IsNullOrWhiteSpace($DeviceUdid)) {
        throw "DeviceUdid is required when -Install is used"
    }
    & tidevice -u $DeviceUdid install $resolvedOutput
    if ($LASTEXITCODE -ne 0) {
        throw "tidevice install failed with exit code $LASTEXITCODE"
    }
}
