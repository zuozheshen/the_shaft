[CmdletBinding()]
param(
    [string]$GodotPath,
    [ValidateSet('All', 'Contracts', 'Existing', 'Smoke')][string]$Check = 'All',
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 180
)

# 单一入口兼容 Windows PowerShell 5.1 和 PowerShell 7；不安装运行时。
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logDirectory = Join-Path ([IO.Path]::GetTempPath()) ('the-shaft-checks-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $logDirectory
Write-Host "Logs: $logDirectory"

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
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        # 只终止本次检查启动的进程树，避免遗留 Godot 或批处理子进程。
        & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
        $process.WaitForExit()
        [IO.File]::WriteAllText($logPath, $stdout.Result + $stderr.Result, [Text.Encoding]::UTF8)
        $process.Dispose()
        throw "TIMEOUT | $Name | $TimeoutSeconds seconds | $logPath"
    }
    $output = $stdout.Result + $stderr.Result
    $exitCode = $process.ExitCode
    $process.Dispose()
    [IO.File]::WriteAllText($logPath, $output, [Text.Encoding]::UTF8)
    # 保留原日志，仅在判定时去掉 ANSI 颜色，防止颜色前缀遮住 ERROR。
    $diagnosticOutput = [regex]::Replace($output, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    $engineErrors = @([regex]::Matches($diagnosticOutput, '(?im)^\s*(?:SCRIPT ERROR:|ERROR:|Parse Error:|FAIL\s*\|).*$'))
    $unexpectedErrors = @($engineErrors | Where-Object {
        $line = $_.Value.Trim()
        $isAllowed = $false
        foreach ($pattern in $AllowedErrorPatterns) {
            if ($line -match $pattern) { $isAllowed = $true; break }
        }
        -not $isAllowed
    })
    if ($exitCode -ne 0 -or $unexpectedErrors.Count -gt 0) {
        Write-Host $output
        throw "CHECK FAILED | $Name | exit=$exitCode | unexpected_errors=$($unexpectedErrors.Count) | $logPath"
    }
    if ($SuccessPattern -and $diagnosticOutput -notmatch $SuccessPattern) {
        Write-Host $output
        throw "INCOMPLETE | $Name | required completion marker missing | $logPath"
    }
    $warningCount = [regex]::Matches($diagnosticOutput, '(?im)^\s*WARNING:').Count
    Write-Host "PASS | $Name | exit=$exitCode | warnings=$warningCount | allowed_diagnostics=$($engineErrors.Count - $unexpectedErrors.Count) | $logPath"
    return $output
}

try {
    $script:engineCommand = Resolve-GodotCommand
    Write-Host "Godot: $script:engineCommand"
    $version = Invoke-GodotCheck 'version' @('--version') '(?m)^4\.7(?:\.|-)'
    $projectFiles = @(Find-ProjectRoots $projectRoot)
    $expectedProject = Join-Path $projectRoot 'project.godot'
    if ($projectFiles.Count -ne 1 -or $projectFiles[0] -ne $expectedProject) {
        throw "PROJECT ROOT | expected only $expectedProject | found: $($projectFiles -join ', ')"
    }
    foreach ($required in @('tests/flow_test_runner.tscn', 'tests/project_check_runner.tscn')) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $required) -PathType Leaf)) {
            throw "Missing required file: $required"
        }
    }
    $commonArguments = @('--headless', '--path', $projectRoot)
    if ($Check -eq 'All') {
        # Godot 4.7 可能在首次扫描 UID 缓存前，先读取 project.godot 并误报入口 UID 未识别。
        # 只允许当前配置值这一条；后续 Validator 必须解析到正式路径，main smoke 也必须通过。
        $projectText = [IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
        $mainUidMatch = [regex]::Match($projectText, 'run/main_scene="(uid://[^"]+)"')
        if (-not $mainUidMatch.Success) { throw 'project.godot must configure run/main_scene with a UID.' }
        $escapedMainUid = [regex]::Escape($mainUidMatch.Groups[1].Value)
        $allowedUidDiagnostic = '^ERROR: Unrecognized UID: "' + $escapedMainUid + '"\.$'
        $null = Invoke-GodotCheck 'editor-import' ($commonArguments + @('--editor', '--import')) 'Godot Engine v4\.7' @($allowedUidDiagnostic)
    }
    if ($Check -in @('All', 'Contracts')) {
        $null = Invoke-GodotCheck 'scene-contracts' ($commonArguments + @('--scene', 'res://tests/project_check_runner.tscn')) 'PROJECT CHECKS PASS'
    }
    if ($Check -in @('All', 'Existing')) {
        $flowOutput = Invoke-GodotCheck 'existing-tests' ($commonArguments + @('--scene', 'res://tests/flow_test_runner.tscn')) '=== 测试汇总：通过 \d+，失败 0 ==='
        Write-Host ([regex]::Match($flowOutput, '=== 测试汇总：[^\r\n]+').Value)
    }
    # 不指定场景：验证 project.godot 的真实入口；有限帧执行 ready 和延迟注入。
    if ($Check -in @('All', 'Smoke')) {
        $null = Invoke-GodotCheck 'main-smoke' ($commonArguments + @('--quit-after', '120')) 'Godot Engine v4\.7'
    }
    if ($Check -eq 'All') { Write-Host 'ALL CHECKS PASS' }
    else { Write-Host "PARTIAL CHECKS PASS | $Check | not a full validation" }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    [Console]::Error.WriteLine("Remaining dependent checks were not run. Logs: $logDirectory")
    exit 1
}
