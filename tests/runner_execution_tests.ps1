[CmdletBinding()]
param([string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'run_all_tests.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$Group = 'RunnerSelfTest'
$TimeoutSeconds = 15
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('the-shaft-runner-tests-' + [Guid]::NewGuid().ToString('N'))
}
$logDirectory = $OutputDirectory
$null = New-Item -ItemType Directory -Path $logDirectory -ErrorAction Stop
$script:engineCommand = Join-Path $logDirectory 'fixture.ps1'

# 用真实子进程验证退出码、日志与超时，避免改写项目资源或递归跑全量。
$fixture = @'
switch ($args[0]) {
    'success' {
        'ERROR: Unrecognized UID: "uid://fixture".'
        'FIXTURE COMPLETE'
        exit 0
    }
    'long-error' {
        for ($index = 1; $index -le 12; $index++) {
            'x' * 800
            'x' * 800
            "ERROR: failure $index"
            'x' * 800
            'x' * 800
        }
        'FIXTURE COMPLETE'
        exit 0
    }
    'nonzero' { 'FIXTURE COMPLETE'; exit 7 }
    'incomplete' { 'LAST FIXTURE LINE'; exit 0 }
    'timeout' {
        'MODULE SELECTED | stalled_fixture, pending_fixture'
        'MODULE START | stalled_fixture'
        Start-Sleep -Seconds 15
        exit 0
    }
}
'@
[IO.File]::WriteAllText($script:engineCommand, $fixture, [Text.Encoding]::UTF8)
$allowedUid = '^ERROR: Unrecognized UID: "uid://fixture"\.$'
$stageTimer = [Diagnostics.Stopwatch]::StartNew()
$null = Invoke-GodotCheck 'success' @('success') 'FIXTURE COMPLETE' @($allowedUid)

foreach ($case in @(
    @{ Name = 'long-error'; Expected = 'CHECK FAILED.*exit=0.*unexpected_errors=12' },
    @{ Name = 'nonzero'; Expected = 'CHECK FAILED.*exit=7' },
    @{ Name = 'incomplete'; Expected = 'INCOMPLETE.*exit=0' },
    @{ Name = 'timeout'; Expected = 'TIMEOUT' }
)) {
    if ($case.Name -eq 'timeout') { $TimeoutSeconds = 3 }
    $stageTimer = [Diagnostics.Stopwatch]::StartNew()
    $failureOutput = @(& {
        try {
            $null = Invoke-GodotCheck $case.Name @($case.Name) 'FIXTURE COMPLETE' @($allowedUid)
        } catch {
            $_.Exception.Message
        }
    } 6>&1 | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($failureOutput -notmatch $case.Expected) { throw "Unexpected $($case.Name) result: $failureOutput" }
    $excerpt = [regex]::Match($failureOutput, '(?ms)^FAILURE EXCERPT BEGIN\r?\n(.*?)\r?\nFAILURE EXCERPT END')
    if (-not $excerpt.Success -or $excerpt.Groups[1].Length -gt 12000 -or
            [regex]::Split($excerpt.Groups[1].Value, '\r?\n').Count -gt 80) {
        throw "Missing or unbounded excerpt for $($case.Name)"
    }
    $logPath = Join-Path $logDirectory ($case.Name + '.log')
    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "Missing full log for $($case.Name)" }
    if ($case.Name -eq 'long-error') {
        $fullLog = [IO.File]::ReadAllText($logPath)
        if ($fullLog.Length -le 12000 -or $fullLog -notmatch 'ERROR: failure 12' -or
                $excerpt.Groups[1].Value -match 'ERROR: failure 12' -or $failureOutput -notmatch 'excerpt truncated') {
            throw 'Long error log did not retain the hidden failure'
        }
        Write-Host "RUNNER LOG SAMPLE | full_chars=$($fullLog.Length) | excerpt_chars=$($excerpt.Groups[1].Length)"
    }
    if ($case.Name -eq 'incomplete' -and $excerpt.Groups[1].Value -notmatch 'LAST FIXTURE LINE') {
        throw 'Incomplete result lost the tail context'
    }
    if ($case.Name -eq 'timeout' -and ($failureOutput -notmatch 'MODULE INTERRUPTED \| stalled_fixture' -or
            $failureOutput -notmatch 'MODULE NOT COMPLETED \| stalled_fixture, pending_fixture')) {
        throw 'Timeout did not report interrupted and pending modules'
    }
}
Write-Host "RUNNER SELF-TEST PASS | cases=5 | $logDirectory"
