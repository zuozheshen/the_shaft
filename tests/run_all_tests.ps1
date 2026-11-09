[CmdletBinding()]
param(
    [string]$GodotPath,
    [ValidateSet('All', 'Contracts', 'Existing', 'Smoke')][string]$Check = 'All',
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 180,
    [string]$Group = 'All'
)

# 单一入口兼容 Windows PowerShell 5.1 和 PowerShell 7；不安装运行时。

function Resolve-GodotCommand {
    $candidate = $GodotPath
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = $env:GODOT_BIN }
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return $command.Source }
        throw "Godot not found: $candidate. Set -GodotPath or GODOT_BIN to an existing executable."
    }
    foreach ($name in @('godot.cmd', 'godot', 'godot.exe')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return $command.Source }
    }
    throw 'Godot not found. Use -GodotPath <path> or set GODOT_BIN, or add godot.cmd / godot to PATH.'
}

function Find-ProjectRoots([string]$Directory) {
    # 不跟随目录链接；不扫描引擎/Git缓存。嵌套项目即使未跟踪也必须报告。
    foreach ($entry in Get-ChildItem -LiteralPath $Directory -Force) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if ($entry.PSIsContainer) {
            if ($entry.Name -notin @('.git', '.godot')) { Find-ProjectRoots $entry.FullName }
        } elseif ($entry.Name -eq 'project.godot') {
            $entry.FullName
        }
    }
}

function Quote-PowerShellLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Write-FailureExcerpt([string[]]$Lines, [int[]]$ErrorLines) {
    $indices = New-Object 'System.Collections.Generic.SortedSet[int]'
    $truncated = $ErrorLines.Count -gt 10
    if ($ErrorLines.Count -gt 0) {
        foreach ($index in ($ErrorLines | Select-Object -First 10)) {
            for ($near = [Math]::Max(0, $index - 2); $near -le [Math]::Min($Lines.Count - 1, $index + 2); $near++) {
                $null = $indices.Add($near)
            }
        }
    } else {
        $truncated = $Lines.Count -gt 20
        for ($index = [Math]::Max(0, $Lines.Count - 20); $index -lt $Lines.Count; $index++) {
            $null = $indices.Add($index)
        }
    }
    $excerpt = New-Object 'System.Collections.Generic.List[string]'
    $characters = 0
    foreach ($index in $indices) {
        $remaining = 12000 - $characters - [Environment]::NewLine.Length
        if ($excerpt.Count -ge 80 -or $remaining -le 0) { $truncated = $true; break }
        $line = $Lines[$index]
        $limit = [Math]::Min($remaining, 1000)
        if ($line.Length -gt $limit) {
            $line = $line.Substring(0, $limit)
            $truncated = $true
        }
        $excerpt.Add($line)
        $characters += $line.Length + [Environment]::NewLine.Length
    }
    Write-Host 'FAILURE EXCERPT BEGIN'
    Write-Host ($excerpt -join [Environment]::NewLine)
    Write-Host 'FAILURE EXCERPT END'
    if ($truncated) { Write-Host 'Failure excerpt truncated; see the full log.' }
}

function Invoke-GodotCheck(
    [string]$Name,
    [string[]]$Arguments,
    [string]$SuccessPattern,
    [string[]]$AllowedErrorPatterns = @()
) {
    $logPath = Join-Path $logDirectory ($Name + '.log')
    Write-Host "RUN  | $Name"
    # 子 PowerShell 统一处理 .exe/.cmd；单引号逐项编码参数，不拼接 cmd /c 命令。
    # 管道让 Windows 的 GUI 版 Godot 也被等待，日志异步读取以避免缓冲区死锁。
    $argumentLiterals = @($Arguments | ForEach-Object { Quote-PowerShellLiteral $_ })
    $childCode = @"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
`$ErrorActionPreference = 'Continue'
try {
    & $(Quote-PowerShellLiteral $script:engineCommand) @($($argumentLiterals -join ',')) 2>&1 | ForEach-Object { [Console]::WriteLine(`$_.ToString()) }
    if (`$null -eq `$LASTEXITCODE) { exit 2 }
    exit `$LASTEXITCODE
} catch {
    [Console]::Error.WriteLine(`$_.ToString())
    exit 2
}
"@
    $hostName = 'powershell.exe'
    if ($PSVersionTable.PSEdition -eq 'Core') { $hostName = 'pwsh.exe' }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $PSHOME $hostName
    $startInfo.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        # 只终止本次阶段启动的进程树，避免遗留 Godot。
        & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
        $process.WaitForExit()
    }
    $output = $stdout.Result + $stderr.Result
    $exitCode = $process.ExitCode
    $process.Dispose()
    [IO.File]::WriteAllText($logPath, $output, [Text.Encoding]::UTF8)

    # 错误判定使用完整日志；只有展示的摘录受限。
    $diagnosticOutput = [regex]::Replace($output, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    $lines = [regex]::Split($diagnosticOutput, '\r?\n')
    $unexpected = New-Object 'System.Collections.Generic.List[int]'
    $allowedCount = 0
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index].Trim()
        if ($line -notmatch '^(?:SCRIPT ERROR:|ERROR:|Parse Error:|FAIL\s*\|)') { continue }
        $isAllowed = $false
        foreach ($pattern in $AllowedErrorPatterns) {
            if ($line -match $pattern) { $isAllowed = $true; break }
        }
        if ($isAllowed) { $allowedCount++ }
        else { $unexpected.Add($index) }
    }

    $failure = $null
    if ($timedOut) { $failure = "TIMEOUT ($($TimeoutSeconds)s)" }
    elseif ($exitCode -ne 0 -or $unexpected.Count -gt 0) { $failure = 'CHECK FAILED' }
    elseif ($SuccessPattern -and $diagnosticOutput -notmatch $SuccessPattern) {
        $failure = 'INCOMPLETE (required completion marker missing)'
    }
    if ($failure) {
        $ended = @([regex]::Matches($diagnosticOutput, '(?m)^MODULE END \| ([a-z_]+) \|') |
            ForEach-Object { $_.Groups[1].Value })
        $lastStarted = [regex]::Matches($diagnosticOutput, '(?m)^MODULE START \| ([a-z_]+)\r?$') | Select-Object -Last 1
        if ($lastStarted -and $lastStarted.Groups[1].Value -notin $ended) {
            Write-Host "MODULE INTERRUPTED | $($lastStarted.Groups[1].Value)"
        }
        $selection = [regex]::Match($diagnosticOutput, '(?m)^MODULE SELECTED \| ([a-z_, ]+)\r?$')
        if ($selection.Success) {
            $pending = @($selection.Groups[1].Value.Split(',') | ForEach-Object { $_.Trim() } |
                Where-Object { $_ -notin $ended })
            if ($pending.Count -gt 0) { Write-Host "MODULE NOT COMPLETED | $($pending -join ', ')" }
        }
        Write-FailureExcerpt $lines ($unexpected.ToArray())
        throw "$failure | exit=$exitCode | unexpected_errors=$($unexpected.Count) | group=$Group | $logPath"
    }
    $warningCount = [regex]::Matches($diagnosticOutput, '(?im)^\s*WARNING:').Count
    Write-Host "PASS | $Name | elapsed_ms=$($stageTimer.ElapsedMilliseconds) | exit=$exitCode | warnings=$warningCount | allowed_diagnostics=$allowedCount | $logPath"
    return $output
}

# 自测只加载阶段执行函数，避免递归运行完整入口。
if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'
$totalTimer = [Diagnostics.Stopwatch]::StartNew()
$exitStatus = 0
$stage = 'setup'
$stageTimer = $totalTimer
$planned = @()
try {
    $groups = @('All', 'Audio', 'Content', 'Runtime', 'Flow', 'Presentation', 'MainConsole', 'LeftConsole', 'RightConsole', 'Gamepad')
    if ($Group -notin $groups -or ($Group -ne 'All' -and $Check -ne 'Existing')) {
        throw "Invalid -Group '$Group' for -Check $Check. Non-All groups require -Check Existing. Groups: $($groups -join ', ')"
    }
    $Group = $groups | Where-Object { $_ -eq $Group }
    $planned = @('version', 'project-root')
    if ($Check -eq 'All') { $planned += @('runner-self-test', 'editor-import') }
    if ($Check -in @('All', 'Contracts')) { $planned += 'scene-contracts' }
    if ($Check -in @('All', 'Existing')) { $planned += 'existing-tests' }
    if ($Check -in @('All', 'Smoke')) { $planned += 'main-smoke' }

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $logDirectory = Join-Path ([IO.Path]::GetTempPath()) ('the-shaft-checks-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $logDirectory
    Write-Host "Logs: $logDirectory"
    Write-Host "Selection: check=$Check | group=$Group"
    $script:engineCommand = Resolve-GodotCommand
    Write-Host "Godot: $script:engineCommand"

    $stage = 'version'
    $stageTimer = [Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-GodotCheck $stage @('--version') '(?m)^4\.7(?:\.|-)'

    $stage = 'project-root'
    $stageTimer = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "RUN  | $stage"
    $projectFiles = @(Find-ProjectRoots $projectRoot)
    $expectedProject = Join-Path $projectRoot 'project.godot'
    if ($projectFiles.Count -ne 1 -or $projectFiles[0] -ne $expectedProject) {
        throw "PROJECT ROOT | expected only $expectedProject | found: $($projectFiles -join ', ')"
    }
    foreach ($required in @('tests/flow_test_runner.tscn', 'tests/project_check_runner.tscn', 'tests/run_main_smoke.gd')) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $required) -PathType Leaf)) {
            throw "Missing required file: $required"
        }
    }
    if ($Check -eq 'All') {
        # 只放行当前配置的入口 UID 初次扫描诊断；仍需结构验证及正式入口 smoke。
        $projectText = [IO.File]::ReadAllText($expectedProject)
        $mainUidMatch = [regex]::Match($projectText, 'run/main_scene="(uid://[^"]+)"')
        if (-not $mainUidMatch.Success) { throw 'project.godot must configure run/main_scene with a UID.' }
        $allowedUidDiagnostic = '^ERROR: Unrecognized UID: "' + [regex]::Escape($mainUidMatch.Groups[1].Value) + '"\.$'
    }
    Write-Host "PASS | $stage | elapsed_ms=$($stageTimer.ElapsedMilliseconds)"

    $commonArguments = @('--headless', '--path', $projectRoot)
    if ($Check -eq 'All') {
        $stage = 'runner-self-test'
        $stageTimer = [Diagnostics.Stopwatch]::StartNew()
        Write-Host "RUN  | $stage"
        & (Join-Path $PSScriptRoot 'runner_execution_tests.ps1') -OutputDirectory (Join-Path $logDirectory 'runner-self-test')
        Write-Host "PASS | $stage | elapsed_ms=$($stageTimer.ElapsedMilliseconds)"

        $stage = 'editor-import'
        $stageTimer = [Diagnostics.Stopwatch]::StartNew()
        $null = Invoke-GodotCheck $stage ($commonArguments + @('--editor', '--import')) 'Godot Engine v4\.7' @($allowedUidDiagnostic)
    }
    if ($Check -in @('All', 'Contracts')) {
        $stage = 'scene-contracts'
        $stageTimer = [Diagnostics.Stopwatch]::StartNew()
        $contractOutput = Invoke-GodotCheck $stage ($commonArguments + @('--scene', 'res://tests/project_check_runner.tscn')) 'PROJECT CHECKS PASS'
        [regex]::Matches($contractOutput, '(?m)^(?:SCRIPTS CHECKED|SCENES CHECKED|CONTRACT SELF-TESTS) \| \d+') |
            ForEach-Object { Write-Host $_.Value }
    }
    if ($Check -in @('All', 'Existing')) {
        $stage = 'existing-tests'
        $stageTimer = [Diagnostics.Stopwatch]::StartNew()
        $flowArguments = $commonArguments + @('--scene', 'res://tests/flow_test_runner.tscn', '--', "--group=$Group")
        $marker = '(?m)^MODULE SUMMARY \| group=' + [regex]::Escape($Group) +
            ' \| selected=([1-9]\d*) \| completed=\1 \| not_selected=\d+\r?$[\s\S]*=== 测试汇总：通过 \d+，失败 0 ==='
        $flowOutput = Invoke-GodotCheck $stage $flowArguments $marker
        [regex]::Matches($flowOutput, '(?m)^(?:MODULE SUMMARY \| |SLOW MODULE \| |=== 测试汇总：)[^\r\n]+') |
            ForEach-Object { Write-Host $_.Value }
    }
    # 宿主读取真实入口，验证播放和正常关闭后的音频清理。
    if ($Check -in @('All', 'Smoke')) {
        $stage = 'main-smoke'
        $stageTimer = [Diagnostics.Stopwatch]::StartNew()
        $null = Invoke-GodotCheck $stage ($commonArguments + @('--script', 'res://tests/run_main_smoke.gd')) 'MAIN SMOKE READY[\s\S]*AUDIO SHUTDOWN COMPLETE'
    }
    if ($Check -eq 'All') { Write-Host 'ALL CHECKS PASS' }
    else { Write-Host "PARTIAL CHECKS PASS | $Check | group=$Group | not a full validation" }
} catch {
    $exitStatus = 1
    [Console]::Error.WriteLine("FAILED | $stage | elapsed_ms=$($stageTimer.ElapsedMilliseconds) | $($_.Exception.Message)")
    $stageIndex = [Array]::IndexOf($planned, $stage)
    for ($index = $stageIndex + 1; $index -lt $planned.Count; $index++) {
        Write-Host "NOT RUN | $($planned[$index])"
    }
}
Write-Host "TOTAL | check=$Check | group=$Group | elapsed_ms=$($totalTimer.ElapsedMilliseconds) | exit=$exitStatus"
exit $exitStatus
