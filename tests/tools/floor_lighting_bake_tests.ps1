[CmdletBinding()]
param([string]$AsepritePath=$env:ASEPRITE_PATH)
$ErrorActionPreference='Stop'
$rootPath=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$caseRoot=Join-Path $rootPath ('art_source/floors/.staging/lighting-tests-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $caseRoot
Write-Host "Lighting test logs: $caseRoot"
$utf8=[Text.UTF8Encoding]::new($false)
$passed=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "TEST FAIL | $Name"};$script:passed++;Write-Host "PASS | $Name"}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path).Hash}
function Json([string]$Name,$Value){$path=Join-Path $caseRoot ($Name+'.json');[IO.File]::WriteAllText($path,($Value|ConvertTo-Json -Depth 20),$utf8);return $path}
function CopyRequest([hashtable]$Value){$copy=@{};foreach($key in $Value.Keys){$copy[$key]=$Value[$key]};return $copy}
function Quote([string]$Value){return '"'+$Value.Replace('"','\"')+'"'}
function Run([string]$Script,[string]$RequestPath,[string]$Name){
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=$AsepritePath
 $info.Arguments=(@('--batch','--script-param',('request='+$RequestPath),'--script',$Script)|ForEach-Object{Quote $_}) -join ' '
 $info.WorkingDirectory=$rootPath;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($info)
 $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
 if(-not $p.WaitForExit(55000)){$p.Kill();throw 'Aseprite test timeout'}
 $output=$stdout.Result+$stderr.Result
 [IO.File]::WriteAllText((Join-Path $caseRoot ($Name+'.log')),$output,$utf8)
 return @{exit_code=$p.ExitCode;text=$output}
}
function Export($Source,[string]$Name){
 $dir=Join-Path $caseRoot $Name;$null=New-Item -ItemType Directory -Path $dir
 $exportRequest=@{action='Export';request_id=$Name;source=$Source;canvas=@(541,272);palette=$palette;layers=$exportLayers;output_directory=$dir;preview=(Join-Path $dir 'composite.png');report=(Join-Path $dir 'report.json')}
 $result=Run $exporter (Json ('export-'+$Name) $exportRequest) ('export-'+$Name)
 Check ($result.exit_code -eq 0 -and $result.text -match 'FLOOR_PIPELINE_OK') ('strict export '+$Name)
 return $dir
}
try{
 if(-not (Test-Path -LiteralPath $AsepritePath -PathType Leaf)){throw 'Pass -AsepritePath / ASEPRITE_PATH'}
 $source=Join-Path $rootPath 'art_source/floors/318/floor_318_art09_surface_v1.aseprite'
 $golden=Join-Path $rootPath 'art_source/floors/318/floor_318_art09_lighting_v1.aseprite'
 Check ((Hash $source) -eq 'EFC5E04E5C9330E5AFE5648A32B16213F0ECD4E4470F8E32A20A187EA670E33F') 'frozen Surface fixture'
 Check ((Hash $golden) -eq 'B3C0F830A643A10CD0BC7A8376E22237EE2C901F564666A6804830DBE44F66FF') 'frozen Lighting V1 fixture'
 $baker=Join-Path $rootPath 'tools/aseprite/bake_floor_lighting.lua'
 $exporter=Join-Path $rootPath 'tools/aseprite/floor_pipeline.lua'
 $palette=Get-Content (Join-Path $rootPath 'art_source/floors/318/palette_art09_lighting_v1.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $layout=Get-Content (Join-Path $rootPath 'art_source/floors/floor_slice_layout_v1.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $layers=@($layout.layers|ForEach-Object{$rect=$layout.status.final_export_rectangles.($_.id);@{id=$_.id;width=$rect[0];height=$rect[1];size=$_.quad_size_m;origin=$_.stage_transform.origin}})
 $exportLayers=@{};foreach($g in $layers){$exportLayers[$g.id]=@{width=$g.width;height=$g.height}}
 $recipe=Join-Path $rootPath 'art_source/floors/318/lighting_recipe_art09_v1.json'
 $masks=Join-Path $rootPath 'art_source/floors/318/lighting_regions_art09_v1.json'
 $request=@{source=$source;output=(Join-Path $caseRoot 'rebuilt.aseprite');report=(Join-Path $caseRoot 'bake-report.json');surface_gate=2;density=64;canvas=@(541,272);palette=$palette;layers=$layers;recipe=$recipe;masks=$masks}
 $baked=Run $baker (Json 'bake-request' $request) 'bake'
 Check ($baked.exit_code -eq 0 -and $baked.text -match 'FLOOR LIGHTING BAKE PASS') 'real separated V1 bake'
 $report=Get-Content $request.report -Raw -Encoding UTF8|ConvertFrom-Json
 Check (@($report.layers|Where-Object{$_.alpha_changes -ne 0}).Count -eq 0) 'all alpha silhouettes preserved'
 $expected=Export $golden 'golden';$actual=Export $request.output 'rebuilt'
 foreach($g in $layers){Check ((Hash (Join-Path $expected ($g.id+'.png'))) -eq (Hash (Join-Path $actual ($g.id+'.png')))) ('V1 exact PNG '+$g.id)}
 # 错误引用必须在另存前拒绝，不能留半成品或覆盖既有源。
 $bad=CopyRequest $request;$bad['output']=Join-Path $caseRoot 'bad-mask.aseprite';$bad['report']=Join-Path $caseRoot 'bad-mask-report.json'
 $badRecipe=Get-Content $recipe -Raw -Encoding UTF8|ConvertFrom-Json;$badRecipe.layers.far.model.fields[0].mask='missing_mask'
 $bad['recipe']=Json 'bad-mask-recipe' $badRecipe
 $result=Run $baker (Json 'bad-mask-request' $bad) 'bad-mask'
 Check ($result.exit_code -ne 0 -and $result.text -match 'Unknown mask' -and -not (Test-Path $bad.output)) 'unknown mask rejected before save'
 $bad=CopyRequest $request;$bad['output']=Join-Path $caseRoot 'missing-layer.aseprite';$bad['report']=Join-Path $caseRoot 'missing-layer-report.json'
 $badRecipe=Get-Content $recipe -Raw -Encoding UTF8|ConvertFrom-Json;$badRecipe.layers.PSObject.Properties.Remove('far');$bad['recipe']=Json 'missing-layer-recipe' $badRecipe
 $result=Run $baker (Json 'missing-layer-request' $bad) 'missing-layer'
 Check ($result.exit_code -ne 0 -and $result.text -match 'Missing layer recipe' -and -not (Test-Path $bad.output)) 'missing recipe layer rejected'
 $before=Hash $request.output;$again=CopyRequest $request;$again['report']=Join-Path $caseRoot 'overwrite-report.json'
 $result=Run $baker (Json 'overwrite-request' $again) 'overwrite'
 Check ($result.exit_code -ne 0 -and $result.text -match 'Refusing existing output' -and (Hash $request.output) -eq $before) 'existing output preserved'
 # 一个两色、单层、小尺寸fixture证明工具不依赖318层名/127色/64px密度。
 $fixture=Join-Path $caseRoot 'fixture.lua'
 [IO.File]::WriteAllText($fixture,@'
local r=json.decode(io.open(app.params.request,'rb'):read('*a'))
local s=Sprite(2,2,ColorMode.RGB);s.layers[1].name='panel'
local p=Palette(2);p:setColor(0,Color{r=0,g=0,b=0,a=0});p:setColor(1,Color{r=255,g=255,b=255,a=255});s:setPalette(p)
local i=Image(2,2,ColorMode.RGB);i:clear();i:drawPixel(0,0,app.pixelColor.rgba(255,255,255,255))
if s.layers[1]:cel(1) then s:deleteCel(s.layers[1],1) end
s:newCel(s.layers[1],1,i,Point(0,0));s:saveCopyAs(r.output);s:close();print('FIXTURE PASS')
'@,$utf8)
 $tinySource=Join-Path $caseRoot 'tiny.aseprite'
 $result=Run $fixture (Json 'fixture-request' @{output=$tinySource}) 'fixture'
 Check ($result.exit_code -eq 0 -and $result.text -match 'FIXTURE PASS') 'independent two-color fixture'
 $tiny=@{source=$tinySource;output=(Join-Path $caseRoot 'tiny-baked.aseprite');report=(Join-Path $caseRoot 'tiny-report.json');surface_gate=2;density=32;canvas=@(2,2);palette=@{art_approved=$false;colors=@(@(0,0,0,0),@(255,255,255,255))};layers=@(@{id='panel';width=2;height=2;size=@(1,1);origin=@(0,0,0)});recipe=(Json 'tiny-recipe' @{schema_version=1;id='test';density=32;layers=@{panel=@{coordinates='vertical';passthrough=$true}}});masks=(Json 'tiny-masks' @{schema_version=1;id='test';masks=@{}})}
 $result=Run $baker (Json 'tiny-request' $tiny) 'tiny-bake'
 Check ($result.exit_code -eq 0 -and $result.text -match 'FLOOR LIGHTING BAKE PASS') 'different layer name/palette/density accepted'
 $tinyReport=Get-Content $tiny.report -Raw -Encoding UTF8|ConvertFrom-Json
 Check ($tinyReport.palette_entries -eq 2 -and $tinyReport.layers[0].changed_pixels -eq 0) 'two-color passthrough pixels preserved'
 Check ((Hash $source) -eq 'EFC5E04E5C9330E5AFE5648A32B16213F0ECD4E4470F8E32A20A187EA670E33F') 'Surface fixture unchanged'
 Check ((Hash $golden) -eq 'B3C0F830A643A10CD0BC7A8376E22237EE2C901F564666A6804830DBE44F66FF') 'V1 fixture unchanged'
 Write-Host "LIGHTING BAKE TESTS PASS | $passed checks | $caseRoot"
 exit 0
}catch{$message=$_.Exception.Message;[Console]::Error.WriteLine('TEST FAIL | '+$message.Substring(0,[Math]::Min(600,$message.Length))+' | '+$_.ScriptStackTrace);exit 1}
