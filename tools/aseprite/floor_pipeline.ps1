[CmdletBinding()]
param(
 [ValidateSet('Inspect','CreateTemplate','PrepareReferenceCopy','Validate','Export')][string]$Action='Inspect',
 [ValidateSet('318')][string]$FloorId='318',
 [string]$Source='art_source/floors/318/floor_318.aseprite',
 [string]$Destination,[string]$Reference, [Alias("Palette")][string]$PaletteFile="art_source/floors/318/pipeline_test_palette.json",
 [ValidateSet(48,64,80)][int]$PixelDensity=64,
 [string]$AsepritePath,[string]$GodotPath,[string]$OutputDirectory,
 [switch]$BindProfile,[switch]$VerifyGodot,[switch]$Diagnostic,
 [ValidateRange(0,16)][int]$DiagnosticFailAfter=0,
 [ValidateRange(1,600)][int]$TimeoutSeconds=120
)
$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$utf8=[Text.UTF8Encoding]::new($false)
$ids=@('far','main','mid_left','mid_right','ground','front_left','front_right')
$lockStream=$null
$jobPath=$null
$sourceHash=$null
$published=[Collections.Generic.List[object]]::new()

function Safe-Path([string]$Value,[string[]]$Prefixes) {
 if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '[\x00\r\n]') { throw 'Missing/invalid path' }
 $path=$Value
 if (-not [IO.Path]::IsPathRooted($path)) { $path=Join-Path $rootPath $path }
 $path=[IO.Path]::GetFullPath($path)
 $accepted=$false
 foreach ($prefix in $Prefixes) {
  $limit=[IO.Path]::GetFullPath((Join-Path $rootPath $prefix)).TrimEnd('\')
  if ($path.Equals($limit,[StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith($limit+'\',[StringComparison]::OrdinalIgnoreCase)) { $accepted=$true }
 }
 if (-not $accepted) { throw "Path outside allowed scope: $Value" }
 $cursor=$path
 while ($cursor.Length -ge $rootPath.Length) {
  if (Test-Path -LiteralPath $cursor) {
   if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse path rejected: $cursor" }
  }
  if ($cursor.Equals($rootPath,[StringComparison]::OrdinalIgnoreCase)) { break }
  $cursor=Split-Path -Parent $cursor
 }
 return $path
}
function Write-Lf([string]$Path,[string]$Content) { [IO.File]::WriteAllText($Path,$Content.Replace("`r`n","`n").TrimEnd()+"`n",$utf8) }
function File-Hash([string]$Path) {
 if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
 return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Text-Hash([string]$Path) {
 $hash = [Security.Cryptography.SHA256]::Create()
 return [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($Path).Replace("`r`n","`n")))).Replace('-','').ToLowerInvariant()
}
function Relative-Path([string]$Path) { return $Path.Substring($rootPath.Length+1).Replace('\','/') }
function Argument-Quote([string]$Value) {
 if ($Value -match '[\x00\r\n]') { throw 'Invalid process argument' }
 $escaped=[regex]::Replace($Value,'(\\*)"','$1$1\"')
 $escaped=[regex]::Replace($escaped,'(\\+)$','$1$1')
 return '"'+$escaped+'"'
}
function Resolve-Exe([string]$Explicit,[string]$EnvironmentValue,[string[]]$Names) {
 $candidate=$Explicit
 if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate=$EnvironmentValue }
 if (-not [string]::IsNullOrWhiteSpace($candidate)) {
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
  $found=Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $found) { return $found.Source }
  throw "Executable not found: $candidate"
 }
 foreach ($name in $Names) {
  $found=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $found) { return $found.Source }
 }
 if ('aseprite.exe' -in $Names) {
  $programFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  foreach ($candidate in @((Join-Path $env:ProgramFiles 'Aseprite/aseprite.exe'),(Join-Path $programFilesX86 'Steam/steamapps/common/Aseprite/aseprite.exe'))) {
   if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
 }
 throw 'Set executable parameter/environment; no installation is performed.'
}
function Invoke-Native([string]$Exe,[string[]]$Arguments,[string]$LogName) {
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName=$Exe
 $start.Arguments=(($Arguments | ForEach-Object { Argument-Quote $_ }) -join ' ')
 if ([IO.Path]::GetExtension($Exe) -eq '.cmd') {
  $literalArgs=@($Arguments | ForEach-Object { "'"+$_.Replace("'","''")+"'" })
  $childCode="& '"+$Exe.Replace("'","''")+"' @("+($literalArgs -join ',')+") 2>&1 | ForEach-Object { [Console]::WriteLine(`$_.ToString()) }; exit `$LASTEXITCODE"
  $start.FileName=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $start.Arguments='-NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
 }
 $start.WorkingDirectory=$rootPath
 $start.UseShellExecute=$false
 $start.CreateNoWindow=$true
 $start.RedirectStandardOutput=$true
 $start.RedirectStandardError=$true
 $start.StandardOutputEncoding=[Text.Encoding]::UTF8
 $start.StandardErrorEncoding=[Text.Encoding]::UTF8
 $process=[Diagnostics.Process]::Start($start)
 $stdout=$process.StandardOutput.ReadToEndAsync()
 $stderr=$process.StandardError.ReadToEndAsync()
 if (-not $process.WaitForExit($TimeoutSeconds*1000)) { $process.Kill(); throw "Timeout: $LogName" }
 $result=@{exit_code=$process.ExitCode;stdout=$stdout.Result;stderr=$stderr.Result}
 Write-Lf (Join-Path $jobPath ($LogName+'.log')) ($result.stdout+$result.stderr)
 return $result
}
function Check-Native($Result,[string]$Marker) {
 if ($Result.exit_code -ne 0 -or $Result.stdout -notmatch [regex]::Escape($Marker) -or ($Result.stdout+[char]10+$Result.stderr) -match '(?m)^(?:SCRIPT ERROR:|ERROR:|FLOOR_PIPELINE_FAIL)') {
  throw "Child process rejected; see $jobPath. $($Result.stderr)"
 }
}
function Check-ImportResult($Result) {
 # 与统一入口相同，只允许首次扫描时当前 main UID 的一条精确诊断。
 # 后续 Godot Profile checker 必须验证该 UID 解析到正式 main_3d。
 $projectText=[IO.File]::ReadAllText((Join-Path $rootPath 'project.godot'))
 $uidMatch=[regex]::Match($projectText,'run/main_scene="(uid://[^"]+)"')
 if (-not $uidMatch.Success) { throw 'Missing configured main UID' }
 $sceneText=[IO.File]::ReadAllText((Join-Path $rootPath 'scenes/main/main_3d.tscn'))
 if ($sceneText -notmatch [regex]::Escape('uid="'+$uidMatch.Groups[1].Value+'"')) { throw 'Configured main UID does not match formal scene' }
 $pattern='(?m)^ERROR: Unrecognized UID: "'+[regex]::Escape($uidMatch.Groups[1].Value)+'"\.\r?$'
 $count=[regex]::Matches($Result.stdout+[char]10+$Result.stderr,$pattern).Count
 if ($count -gt 1) { throw 'Repeated main UID diagnostic' }
 $filtered=$Result.Clone()
 $filtered.stdout=[regex]::Replace($Result.stdout,$pattern,'')
 $filtered.stderr=[regex]::Replace($Result.stderr,$pattern,'')
 Check-Native $filtered 'Godot Engine v4.7'
 if ($count -eq 1) { Write-Host 'IMPORT | allowed exact main UID bootstrap diagnostic=1; resolution checked next' }
}

function Profile-Candidate([string]$Text) {
 $text=$Text.Replace("`r`n","`n")
 if ($text -notmatch 'script_class="FloorVisualProfile"' -or $text -notmatch '(?m)^floor_id = &"318"$') { throw 'Profile identity mismatch' }
 foreach ($id in $ids) {
  $field='(?m)^'+[regex]::Escape($id)+'_texture\s*=.*\n?'
  $match=[regex]::Match($text,$field)
  if ($match.Success -and $match.Value.Trim() -ne ($id+'_texture = ExtResource("pipeline_'+$id+'")')) { throw "Unmanaged texture binding: $id" }
  $text=[regex]::Replace($text,$field,'')
  $declaration='(?m)^\[ext_resource type="Texture2D" path="res://assets/art/floors/318/'+$id+'\.png" id="pipeline_'+$id+'"\]\n?'
  $text=[regex]::Replace($text,$declaration,'')
 }
 $text=[regex]::Replace($text,'\n{3,}',[string][char]10+[char]10)
 if ([regex]::Matches($text,'(?m)^\[resource\]$').Count -ne 1) { throw 'Ambiguous Profile resource section' }
 $declarations=@($ids | ForEach-Object { '[ext_resource type="Texture2D" path="res://assets/art/floors/318/'+$_+'.png" id="pipeline_'+$_+'"]' }) -join "`n"
 $bindings=@($ids | ForEach-Object { $_+'_texture = ExtResource("pipeline_'+$_+'")' }) -join "`n"
 $text=$text.Replace('[resource]',$declarations+"`n`n[resource]")
 $text=$text.TrimEnd()+"`n"+$bindings+"`n"
 $steps=[regex]::Matches($text,'(?m)^\[(?:ext_resource|sub_resource) ').Count+1
 if ([regex]::Matches($text,'load_steps=\d+').Count -ne 1) { throw 'Ambiguous Profile load_steps' }
 return [regex]::Replace($text,'load_steps=\d+','load_steps='+$steps)
}
function Import-Candidate([string]$Path,[string]$Id) {
 $sourceLine='source_file="res://assets/art/floors/318/'+$Id+'.png"'
 if (Test-Path -LiteralPath $Path) {
  $text=[IO.File]::ReadAllText($Path).Replace("`r`n","`n")
  if ($text -notmatch [regex]::Escape($sourceLine) -or $text -notmatch 'importer="texture"') { throw 'Import identity mismatch' }
 } else {
  $text='[remap]'+"`n"+'importer="texture"'+"`n"+'type="CompressedTexture2D"'+"`n`n[deps]`n"+$sourceLine+"`n`n[params]`n"
 }
 $settings=[ordered]@{'compress/mode'='0';'mipmaps/generate'='false';'process/fix_alpha_border'='false';'process/premult_alpha'='false';'process/size_limit'='0';'detect_3d/compress_to'='0'}
 foreach ($setting in $settings.GetEnumerator()) {
  $pattern='(?m)^'+[regex]::Escape($setting.Key)+'=.*$'
  if ([regex]::IsMatch($text,$pattern)) { $text=[regex]::Replace($text,$pattern,$setting.Key+'='+$setting.Value) }
  else { $text=$text.TrimEnd()+"`n"+$setting.Key+'='+$setting.Value+"`n" }
 }
 return $text
}
function Accept-ImportNormalization {
 foreach ($entry in $published) {
  if (-not $entry.target.EndsWith('.png.import')) { continue }
  $text = [IO.File]::ReadAllText($entry.target)
  $name = [IO.Path]::GetFileName($entry.target).Replace('.png.import','')
  if ($name -notin $ids -or $text -notmatch [regex]::Escape('source_file="res://assets/art/floors/318/'+$name+'.png"')) { throw 'Unexpected import normalization identity' }
  foreach ($row in @('compress/mode=0','mipmaps/generate=false','process/fix_alpha_border=false','process/premult_alpha=false','process/size_limit=0','detect_3d/compress_to=0')) {
   if ($text -notmatch ('(?m)^'+[regex]::Escape($row)+'\r?$')) { throw 'Import changed pixel settings; preserve it' }
  }
  # 本次受控 importer 只补 UID/path/default 元数据；记录其新 hash 以便失败时精确恢复。
  $entry.new_hash = File-Hash $entry.target
 }
 Write-Lf (Join-Path $jobPath 'recovery-journal.json') ($targets | ConvertTo-Json -Depth 8)
}
function Restore-Published {
 $unrestored=@()
 for ($i=$published.Count-1;$i -ge 0;$i--) {
  $entry=$published[$i]
  if ((File-Hash $entry.target) -ne $entry.new_hash) { $unrestored+=$entry.target; continue }
  if ($entry.existed) { Copy-Item -LiteralPath $entry.backup -Destination $entry.target -Force }
  else { Remove-Item -LiteralPath $entry.target }
 }
 if ($unrestored.Count -gt 0) { throw "Rollback preserved concurrently modified files; journal: $jobPath" }
}
try {
 if (-not (Test-Path -LiteralPath (Join-Path $rootPath 'project.godot'))) { throw 'Missing project.godot' }
 $stageRoot=Safe-Path 'art_source/floors/.staging' @('art_source/floors/.staging')
 $null=New-Item -ItemType Directory -Path $stageRoot -Force
 $lockStream=[IO.File]::Open((Join-Path $stageRoot 'floor-318.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $jobPath=Join-Path $stageRoot ([Guid]::NewGuid().ToString('N'))
 $null=New-Item -ItemType Directory -Path $jobPath
 $exe=Resolve-Exe $AsepritePath $env:ASEPRITE_PATH @('aseprite.exe','aseprite')
 $version=Invoke-Native $exe @('--version') 'version'
 if ($version.exit_code -ne 0 -or $version.stdout -notmatch '^Aseprite 1\.3\.') { throw 'Aseprite 1.3.x required' }
 $sourcePath=Safe-Path $Source @('art_source/floors/318','art_source/floors/.staging')
 if ([IO.Path]::GetExtension($sourcePath) -ne '.aseprite') { throw 'Source must be .aseprite' }
 if ($Action -eq 'CreateTemplate') {
  if (Test-Path -LiteralPath $sourcePath) { throw 'CreateTemplate refuses existing source' }
 } else {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw 'Saved source not found' }
  $sourceHash=File-Hash $sourcePath
 }
 $manifestPath=Join-Path $rootPath 'art_source/floors/floor_slice_layout_v1.json'
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if ($manifest.status.geometry -ne 'runtime_verified' -or $manifest.layers.Count -ne 7) { throw 'Pass B layout gate failed' }
 if (-not $Diagnostic -and -not $manifest.status.export_ready) { throw 'Final D/Palette not approved; use -Diagnostic for C1/C2' }
 $palettePath=Safe-Path $PaletteFile @('art_source/floors/318')
 $palette=Get-Content -LiteralPath $palettePath -Raw -Encoding UTF8 | ConvertFrom-Json
 if ($Diagnostic) {
  if ($palette.art_approved) { throw 'Diagnostic fixtures must not be labelled art-approved' }
 } elseif (-not $palette.art_approved -or $manifest.status.palette_id -ne $palette.id -or $manifest.status.final_pixel_density_px_per_m -ne $PixelDensity -or $manifest.status.palette_sha256 -ne (Text-Hash $palettePath)) {
  throw 'Final density/palette gate mismatch'
 }
 foreach ($fingerprint in $manifest.provenance.sources.PSObject.Properties) {
  $layoutSource = Safe-Path $fingerprint.Name @('scenes','scripts')
  if ((Text-Hash $layoutSource) -ne $fingerprint.Value) { throw "Pass B source fingerprint changed: $($fingerprint.Name)" }
 }
 $geometry=[ordered]@{}
 $canvasW=0; $canvasH=0
 foreach ($layer in $manifest.layers) {
  if ($layer.id -notin $ids -or $geometry.Contains($layer.id)) { throw 'Layout layer ID mismatch' }
  $width=[int][Math]::Ceiling([decimal]$layer.quad_size_m[0]*$PixelDensity)
  $height=[int][Math]::Ceiling([decimal]$layer.quad_size_m[1]*$PixelDensity)
  $geometry[$layer.id]=@{id=$layer.id;width=$width;height=$height;size=$layer.quad_size_m;origin=$layer.local_transform.origin}
  $canvasW=[Math]::Max($canvasW,$width); $canvasH=[Math]::Max($canvasH,$height)
 }
 $requestId=[Guid]::NewGuid().ToString('N')
 $reportPath=Join-Path $jobPath 'lua-report.json'
 $pngStage=Join-Path $jobPath 'png'
 $null=New-Item -ItemType Directory -Path $pngStage
 $request=@{action=$Action;request_id=$requestId;source=$sourcePath;report=$reportPath;canvas=@($canvasW,$canvasH);
  layers=$geometry;palette=$palette;density=$PixelDensity;output_directory=$pngStage;
  output_source=(Join-Path $jobPath 'created.aseprite');preview=(Join-Path $jobPath 'asset-preview.png')}
 if ($Action -eq 'PrepareReferenceCopy') {
  $referencePath=Safe-Path $Reference @('art_source/floors/318','art_source/floors/.staging')
  if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) { throw 'Reference not found' }
  $destinationPath=Safe-Path $Destination @('art_source/floors/318','art_source/floors/.staging')
  if ($destinationPath -eq $sourcePath -or (Test-Path -LiteralPath $destinationPath) -or [IO.Path]::GetExtension($destinationPath) -ne '.aseprite') { throw 'Reference copy must use new .aseprite path' }
  $request.reference=$referencePath
 }
 Write-Lf (Join-Path $jobPath 'request.json') ($request | ConvertTo-Json -Depth 32)
 $result=Invoke-Native $exe @('--batch','--script-param',('request='+(Join-Path $jobPath 'request.json')),'--script',(Join-Path $PSScriptRoot 'floor_pipeline.lua')) 'aseprite'
 Check-Native $result ('FLOOR_PIPELINE_OK '+$requestId)
 $luaReport=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if (-not $luaReport.ok -or $luaReport.request_id -ne $requestId) { throw 'Unverified Lua report' }
 if ($sourceHash -and (File-Hash $sourcePath) -ne $sourceHash) { throw 'Saved source changed during batch' }
 if ($Action -in @('CreateTemplate','PrepareReferenceCopy')) {
  $target=$sourcePath
  if ($Action -eq 'PrepareReferenceCopy') { $target=$destinationPath }
  $null=New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
  [IO.File]::Move($request.output_source,$target) # Never overwrite, including after a race.
  Write-Host "CREATED | $(Relative-Path $target) | sha256=$(File-Hash $target)"
 } elseif ($Action -eq 'Export') {
  $defaultOutput=Join-Path $rootPath 'assets/art/floors/318'
  $output=$defaultOutput
  if ($OutputDirectory) { $output=Safe-Path $OutputDirectory @('art_source/floors/.staging','art_source/floors/.preview') }
  if ($BindProfile -and $output -ne $defaultOutput) { throw 'BindProfile only supports formal 318 paths' }
  if ($VerifyGodot -and -not $BindProfile) { throw 'VerifyGodot requires BindProfile' }
  if ($DiagnosticFailAfter -gt 0 -and $output -eq $defaultOutput) { throw 'Fault injection is limited to ignored test output' }
  $output=Safe-Path $output @('assets/art/floors/318','art_source/floors/.staging','art_source/floors/.preview')
  $null=New-Item -ItemType Directory -Path $output -Force
  $receiptPath=Join-Path $output 'pipeline_receipt.json'
  $oldReceipt=$null
  if (Test-Path -LiteralPath $receiptPath) {
   $oldReceipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
   if ($oldReceipt.producer -ne 'the-shaft-floor-pipeline-v1' -or $oldReceipt.floor_id -ne '318' -or $oldReceipt.pngs.Count -ne 7) { throw 'Unowned output receipt' }
  }
  if ($Diagnostic -and $output -eq $defaultOutput -and $oldReceipt -and $oldReceipt.art_palette_approved) { throw 'Approved art output requires approved pipeline inputs' }
  foreach ($id in $ids) {
   $target=Join-Path $output ($id+'.png')
   if (Test-Path -LiteralPath $target) {
    $owned=@($oldReceipt.pngs | Where-Object { $_.id -eq $id })
    if ($owned.Count -ne 1 -or (File-Hash $target) -ne $owned[0].sha256) { throw "Unowned/modified PNG: $id" }
   }
  }
  if (@(Get-ChildItem -LiteralPath $pngStage -File -Filter '*.png').Count -ne 7) { throw 'Expected exactly seven staged PNGs' }
  $pngs=@()
  $targets=[Collections.Generic.List[object]]::new()
  foreach ($id in $ids) {
   $staged=Join-Path $pngStage ($id+'.png')
   $bytes=[IO.File]::ReadAllBytes($staged)
   if ($bytes.Length -lt 33 -or [BitConverter]::ToString($bytes[0..7]) -ne '89-50-4E-47-0D-0A-1A-0A' -or $bytes[24] -ne 8 -or $bytes[25] -ne 6) { throw "PNG must be lossless 8-bit RGBA: $id" }
   $w=[Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes,16))
   $h=[Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes,20))
   if ($w -ne $geometry[$id].width -or $h -ne $geometry[$id].height) { throw "Wrong PNG size: $id" }
   $stats=@($luaReport.pngs | Where-Object { $_.id -eq $id })[0]
   $pngs+=@{id=$id;file=$id+'.png';width=$w;height=$h;sha256=(File-Hash $staged);opaque=$stats.opaque;transparent=$stats.transparent;color_count=$stats.color_count}
   $targets.Add(@{staged=$staged;target=(Join-Path $output ($id+'.png'))})
   if ($output -eq $defaultOutput) {
    $importPath=Join-Path $output ($id+'.png.import')
    if ((Test-Path -LiteralPath $importPath) -and -not $oldReceipt) { throw "Unowned import: $id" }
    $importStage=Join-Path $jobPath ($id+'.png.import')
    Write-Lf $importStage (Import-Candidate $importPath $id)
    $targets.Add(@{staged=$importStage;target=$importPath})
   }
  }
  $profilePath=Join-Path $rootPath 'data/presentation/floor_visuals/floor_318_visual.tres'
  $profileHash=$null
  if ($BindProfile) {
   if ($oldReceipt -and $oldReceipt.profile_sha256 -and (Text-Hash $profilePath) -ne $oldReceipt.profile_sha256) { throw 'Profile changed since last managed export' }
   $candidate=Join-Path $jobPath 'profile.tres'
   Write-Lf $candidate (Profile-Candidate ([IO.File]::ReadAllText($profilePath)))
   $profileHash=Text-Hash $candidate
   $targets.Add(@{staged=$candidate;target=$profilePath})
  }
  $assetStage='structural_test_only'
  if (-not $Diagnostic) {
   $assetStage='residential_art_v1'
   if ($palette.asset_stage) {
    if ($palette.asset_stage -notin @('residential_art_v1','residential_art_v2')) { throw 'Unknown approved art stage' }
    $assetStage=$palette.asset_stage
   }
  }
  $receipt=[ordered]@{schema_version=1;producer='the-shaft-floor-pipeline-v1';floor_id='318';asset_stage=$assetStage;
   density_candidate=$PixelDensity;art_palette_approved=[bool]$palette.art_approved;palette_id=$palette.id;palette_colors=$palette.colors;
   palette_source=(Relative-Path $palettePath);palette_sha256=(Text-Hash $palettePath);source=(Relative-Path $sourcePath);source_sha256=$sourceHash;
   layout_sha256=(Text-Hash $manifestPath);canvas=@($canvasW,$canvasH);pngs=$pngs;profile_sha256=$profileHash;source_disk_only=$true}
  $receiptStage=Join-Path $jobPath 'pipeline_receipt.json'
  Write-Lf $receiptStage ($receipt | ConvertTo-Json -Depth 32)
  $targets.Add(@{staged=$receiptStage;target=$receiptPath})
  $backupDir=Join-Path $jobPath 'backup'
  $null=New-Item -ItemType Directory -Path $backupDir
  for ($i=0;$i -lt $targets.Count;$i++) {
   $entry=$targets[$i]
   $entry.existed=Test-Path -LiteralPath $entry.target -PathType Leaf
   $entry.old_hash=File-Hash $entry.target
   $entry.new_hash=File-Hash $entry.staged
   $entry.backup=Join-Path $backupDir ('file-'+$i)
   if ($entry.existed) { Copy-Item -LiteralPath $entry.target -Destination $entry.backup }
  }
  Write-Lf (Join-Path $jobPath 'recovery-journal.json') ($targets | ConvertTo-Json -Depth 8)
  foreach ($entry in $targets) {
   if ((File-Hash $entry.target) -ne $entry.old_hash) { throw 'Concurrent output modification; publication cancelled' }
   $tempTarget=$entry.target+'.pipeline-'+$requestId+'.tmp'
   [IO.File]::Copy($entry.staged,$tempTarget,$false)
   try {
    if ((File-Hash $entry.target) -ne $entry.old_hash) { throw 'Concurrent output modification before atomic replacement' }
    if ($entry.existed) { [IO.File]::Replace($tempTarget,$entry.target,$entry.backup) }
    else { [IO.File]::Move($tempTarget,$entry.target) }
   } finally {
    if (Test-Path -LiteralPath $tempTarget) { Remove-Item -LiteralPath $tempTarget }
   }
   $published.Add($entry)
   if ($DiagnosticFailAfter -gt 0 -and $published.Count -eq $DiagnosticFailAfter) { throw 'Diagnostic injected publication failure' }
  }
  if ($VerifyGodot) {
   $godot=Resolve-Exe $GodotPath $env:GODOT_BIN @('godot.cmd','godot.exe','godot')
   $importResult=Invoke-Native $godot @('--headless','--path',$rootPath,'--editor','--import') 'godot-import'
   Accept-ImportNormalization
   Check-ImportResult $importResult
   $checkResult=Invoke-Native $godot @('--headless','--path',$rootPath,'--script','res://tools/aseprite/validate_floor_profile.gd','--','--check-profile',('--density='+$PixelDensity)) 'godot-profile'
   Check-Native $checkResult 'FLOOR PROFILE CHECKS PASS'
  }
  foreach ($png in $pngs) { Write-Host "PNG | $($png.id) | $($png.width)x$($png.height) | $($png.sha256)" }
  Write-Host "EXPORT PASS | density=$PixelDensity | source hash unchanged | asset_stage=$assetStage"
 }
 Write-Host "FLOOR PIPELINE PASS | $Action | report=$reportPath"
 @{ok=$true;action=$Action;job=(Relative-Path $jobPath);source_sha256=$sourceHash;report_file=(Relative-Path $reportPath)} | ConvertTo-Json -Depth 12
} catch {
 $reason=$_.Exception.Message
 if ($published.Count -gt 0) {
  try { Restore-Published; Write-Host 'ROLLBACK PASS | restored managed output bytes' }
  catch { $reason+='; '+$_.Exception.Message }
 }
 if ($sourceHash -and (File-Hash $sourcePath) -ne $sourceHash) { $reason+='; saved source hash CHANGED' }
 Write-Error ("FLOOR PIPELINE FAIL | "+$reason) -ErrorAction Continue
 exit 1
} finally { if ($null -ne $lockStream) { $lockStream.Dispose() } }
