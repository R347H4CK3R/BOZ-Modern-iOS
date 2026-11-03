$ErrorActionPreference = 'Stop'
$privateRepo = 'R347H4CK3R/BOZ-Modern-iOS'
$publicRepo = 'R347H4CK3R/BOZ-Strata-Source'
$releaseTag = 'engine-trace-v4'
$staging = Join-Path $env:TEMP ('BOZ-Publish-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
function GhChecked {
    param([string[]]$GhArgs)
    $result = & gh @GhArgs
    if ($LASTEXITCODE -ne 0) { throw ('GitHub command failed: ' + ($GhArgs -join ' ')) }
    return $result
}
function PutFile {
    param([string]$RemotePath,[byte[]]$Bytes)
    $payload = @{message='Publish Strata installation source';content=[Convert]::ToBase64String($Bytes)}
    $existing = & gh api ('repos/'+$publicRepo+'/contents/'+$RemotePath) 2>$null
    if ($LASTEXITCODE -eq 0) { $payload.sha = ($existing | ConvertFrom-Json).sha }
    $bodyPath = Join-Path $staging 'request.json'
    [IO.File]::WriteAllText($bodyPath,($payload | ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
    GhChecked -GhArgs @('api','--method','PUT',('repos/'+$publicRepo+'/contents/'+$RemotePath),'--input',$bodyPath) | Out-Null
}
GhChecked -GhArgs @('release','download',$releaseTag,'--repo',$privateRepo,'--pattern','BOZ-Modern-iOS-unsigned.ipa','--pattern','BOZ-Modern-iOS-unsigned.sha256','--dir',$staging) | Out-Null
$ipa = Join-Path $staging 'BOZ-Modern-iOS-unsigned.ipa'
$checksumFile = Join-Path $staging 'BOZ-Modern-iOS-unsigned.sha256'
$expected = ((Get-Content -LiteralPath $checksumFile -Raw).Trim() -split '\s+')[0]
$actual = (Get-FileHash -LiteralPath $ipa -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected.ToLowerInvariant()) { throw 'IPA checksum mismatch' }
Write-Output ('Verified IPA SHA256: '+$actual)
cmd /c "gh release view $releaseTag --repo $publicRepo >nul 2>&1"
if ($LASTEXITCODE -eq 0) {
    GhChecked -GhArgs @('release','upload',$releaseTag,$ipa,$checksumFile,'--repo',$publicRepo,'--clobber') | Out-Null
} else {
    GhChecked -GhArgs @('release','create',$releaseTag,$ipa,$checksumFile,'--repo',$publicRepo,'--title','BOZ unsigned startup trace v4','--notes','Experimental unsigned compatibility build 135.7. Includes ordered segment layout and startup diagnostics. Package checks passed; on-device launch and gameplay are not verified.','--prerelease') | Out-Null
}
$catalogResponse = (GhChecked -GhArgs @('api',('repos/'+$privateRepo+'/contents/strata-source.json'))) | ConvertFrom-Json
$catalogText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($catalogResponse.content))
$catalogText = $catalogText.Replace($privateRepo,$publicRepo)
$parsed = $catalogText | ConvertFrom-Json
if ($parsed.apps[0].versions[0].buildNumber -ne '135.7') { throw 'Unexpected source build version' }
PutFile -RemotePath 'strata-source.json' -Bytes ([Text.Encoding]::UTF8.GetBytes($catalogText))
$icon = (GhChecked -GhArgs @('api',('repos/'+$privateRepo+'/contents/source-icon.png'))) | ConvertFrom-Json
PutFile -RemotePath 'source-icon.png' -Bytes ([Convert]::FromBase64String($icon.content))
$readme = "# BOZ for Strata\n\nAdd this catalog in Strata Sources:\n\nhttps://raw.githubusercontent.com/$publicRepo/main/strata-source.json\n\nExperimental unsigned compatibility build 135.7. Launch and gameplay remain unverified. Game belongs to Activision. This repository contains installation metadata, the icon, and the packaged compatibility build only. Diagnostic reports and build inputs are kept in a separate private repository.\n"
PutFile -RemotePath 'README.md' -Bytes ([Text.Encoding]::UTF8.GetBytes($readme.Replace('\n',[Environment]::NewLine)))
$buildStatusFile = (GhChecked -GhArgs @('api',('repos/'+$privateRepo+'/contents/diagnostic-build-status.json'))) | ConvertFrom-Json
$buildStatus = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($buildStatusFile.content)) | ConvertFrom-Json
$buildCommit = GhChecked -GhArgs @('run','view',[string]$buildStatus.run_id,'--repo',$privateRepo,'--json','headSha','--jq','.headSha')
PutFile -RemotePath 'SOURCE_COMMIT' -Bytes ([Text.Encoding]::UTF8.GetBytes($buildCommit.Trim()+[Environment]::NewLine))
GhChecked -GhArgs @('repo','view',$publicRepo,'--json','isPrivate,url') 
GhChecked -GhArgs @('release','view',$releaseTag,'--repo',$publicRepo,'--json','assets,url')
Write-Output 'PUBLIC_SOURCE_PUBLISHED'
