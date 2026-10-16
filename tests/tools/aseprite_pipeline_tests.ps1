[CmdletBinding()]
param([string]$AsepritePath = $env:ASEPRITE_PATH)
$ErrorActionPreference = 'Stop'
$rootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source = Join-Path $rootPath 'art_source/floors/318/floor_318.aseprite'
$pipeline = Join-Path $rootPath 'tools/aseprite/floor_pipeline.ps1'
$caseRoot = Join-Path $rootPath ('art_source/floors/.staging/tests-'+[Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $caseRoot
$utf8 = [Text.UTF8Encoding]::new($false)
$passed = 0
function Check([bool]$Value,[string]$Name) {
 if (-not $Value) { throw "TEST FAIL | $Name" }
 $script:passed++
 Write-Host "PASS | $Name"
}
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Quote([string]$Value) { return '"' + $Value.Replace('"','\"') + '"' }
function Run([string]$Exe,[string[]]$Arguments,[string]$LogName) {
 $info = [Diagnostics.ProcessStartInfo]::new()
 $info.FileName = $Exe
 $info.Arguments = (($Arguments | ForEach-Object { Quote $_ }) -join ' ')
 $info.WorkingDirectory = $rootPath
 $info.UseShellExecute = $false
 $info.CreateNoWindow = $true
 $info.RedirectStandardOutput = $true
 $info.RedirectStandardError = $true
 $info.StandardOutputEncoding = [Text.Encoding]::UTF8
 $info.StandardErrorEncoding = [Text.Encoding]::UTF8
 $process = [Diagnostics.Process]::Start($info)
 $stdout = $process.StandardOutput.ReadToEndAsync()
 $stderr = $process.StandardError.ReadToEndAsync()
 if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Fixture process timeout' }
 $text = $stdout.Result + $stderr.Result
 [IO.File]::WriteAllText((Join-Path $caseRoot ($LogName+'.log')),$text,$utf8)
 return @{exit_code=$process.ExitCode;text=$text}
}
function Pipeline([string[]]$Arguments,[string]$Name) {
 return Run ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) (@('-NoProfile','-File',$pipeline,'-AsepritePath',$AsepritePath,'-Diagnostic')+$Arguments) $Name
}
function Fixture([string]$Mode,[string]$Extension='.aseprite') {
 $target = Join-Path $caseRoot ($Mode+$Extension)
 $result = Run $AsepritePath @('--batch','--script-param',('source='+$source),'--script-param',('target='+$target),'--script-param',('mode='+$Mode),'--script',(Join-Path $PSScriptRoot 'aseprite_fixture.lua')) ('fixture-'+$Mode)
 Check ($result.exit_code -eq 0 -and $result.text -match 'FIXTURE PASS') ("fixture "+$Mode)
 return $target
}
try {
 if (-not (Test-Path -LiteralPath $AsepritePath -PathType Leaf)) { throw 'Pass -AsepritePath / ASEPRITE_PATH' }
 $originalHash = Hash $source
 $out = Join-Path $caseRoot 'output'
 $good = Pipeline @('-Action','Export','-OutputDirectory',$out) 'good'
 Check ($good.exit_code -eq 0 -and $good.text -match 'EXPORT PASS') 'real CLI export'
 $before = Get-Content -LiteralPath (Join-Path $out 'pipeline_receipt.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Check (@(Get-ChildItem -LiteralPath $out -Filter '*.png').Count -eq 7) 'exact seven PNG whitelist'
 Check ($before.pngs.id -notcontains 'REFERENCE' -and $before.pngs.id -notcontains 'GUIDES') 'guides/reference excluded'
 $again = Pipeline @('-Action','Export','-OutputDirectory',$out) 'repeat'
 Check ($again.exit_code -eq 0) 'repeat export'
 foreach ($png in $before.pngs) { Check ((Hash (Join-Path $out $png.file)).ToLowerInvariant() -eq $png.sha256) ('repeat hash '+$png.id) }
 Check ((Hash $source) -eq $originalHash) 'source hash unchanged'
 $blocked = Pipeline @('-Action','CreateTemplate') 'refuse-existing-source'
 Check ($blocked.exit_code -ne 0) 'CreateTemplate refuses saved source'
 foreach ($mode in @('hidden_bad','alpha','bounds','missing','duplicate','group','frame','canvas')) {
  $fixture = Fixture $mode
  $result = Pipeline @('-Action','Validate','-Source',$fixture) ('reject-'+$mode)
  Check ($result.exit_code -ne 0 -and $result.text -match 'FLOOR PIPELINE FAIL') ('reject '+$mode)
 }
 $visibleReference = Fixture 'reference_guides'
 $referenceOutput = Join-Path $caseRoot 'reference-output'
 $result = Pipeline @('-Action','Export','-Source',$visibleReference,'-OutputDirectory',$referenceOutput) 'reference-export'
 Check ($result.exit_code -eq 0) 'high-color REFERENCE / visible GUIDES accepted'
 foreach ($png in $before.pngs) { Check ((Hash (Join-Path $referenceOutput $png.file)).ToLowerInvariant() -eq $png.sha256) ('excluded helpers / hidden main '+$png.id) }
 $empty = Fixture 'empty'
 $emptyOutput = Join-Path $caseRoot 'empty-output'
 $result = Pipeline @('-Action','Export','-Source',$empty,'-OutputDirectory',$emptyOutput) 'empty-export'
 Check ($result.exit_code -eq 0 -and @(Get-ChildItem -LiteralPath $emptyOutput -Filter '*.png').Count -eq 7) 'empty formal layer still exports'
 $emptyReceipt = Get-Content -LiteralPath (Join-Path $emptyOutput 'pipeline_receipt.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Check (@($emptyReceipt.pngs | Where-Object { $_.id -eq 'mid_left' })[0].opaque -eq 0) 'empty layer fixed rectangle transparent'
 $referencePng = Fixture 'reference_png' '.png'
 $referenceCopy = Join-Path $caseRoot 'reference-copy.aseprite'
 $result = Pipeline @('-Action','PrepareReferenceCopy','-Reference',$referencePng,'-Destination',$referenceCopy) 'reference-copy'
 Check ($result.exit_code -eq 0 -and (Test-Path -LiteralPath $referenceCopy)) 'reference written only to new copy'
 Check ((Hash $source) -eq $originalHash) 'reference-copy preserves source'
 $copyAgain = Pipeline @('-Action','PrepareReferenceCopy','-Reference',$referencePng,'-Destination',$referenceCopy) 'refuse-existing-copy'
 Check ($copyAgain.exit_code -ne 0) 'existing reference copy protected'
 $receiptHash = Hash (Join-Path $out 'pipeline_receipt.json')
 $fault = Pipeline @('-Action','Export','-OutputDirectory',$out,'-DiagnosticFailAfter','3') 'rollback'
 Check ($fault.exit_code -ne 0 -and $fault.text -match 'ROLLBACK PASS') 'partial publication rollback'
 Check ((Hash (Join-Path $out 'pipeline_receipt.json')) -eq $receiptHash) 'rollback restores receipt bytes'
 foreach ($png in $before.pngs) { Check ((Hash (Join-Path $out $png.file)).ToLowerInvariant() -eq $png.sha256) ('rollback restores '+$png.id) }
 $outside = Pipeline @('-Action','Export','-OutputDirectory','../issue-75-outside') 'outside'
 Check ($outside.exit_code -ne 0) 'outside output rejected'
 $unknown = Join-Path $caseRoot 'unowned'
 $null = New-Item -ItemType Directory -Path $unknown
 Copy-Item -LiteralPath (Join-Path $out 'far.png') -Destination (Join-Path $unknown 'far.png')
 $unownedHash = Hash (Join-Path $unknown 'far.png')
 $unowned = Pipeline @('-Action','Export','-OutputDirectory',$unknown) 'unowned'
 Check ($unowned.exit_code -ne 0 -and (Hash (Join-Path $unknown 'far.png')) -eq $unownedHash) 'unowned output protected'
 $production = Run ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) @('-NoProfile','-File',$pipeline,'-Action','Validate','-AsepritePath',$AsepritePath) 'unapproved-art'
 Check ($production.exit_code -ne 0) 'unapproved final D/palette rejected'
 Check ((Hash $source) -eq $originalHash) 'all negative cases preserve original source'
 Write-Host "ASEPRITE PIPELINE TESTS PASS | $passed checks | logs=$caseRoot"
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }
