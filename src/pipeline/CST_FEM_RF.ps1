# PASSBRIDGE: real FEM-displaced, finite-conductivity CST SBR cases.
# Uses same CSTStudio.Application -> OpenFile -> Active3D -> AddToHistory -> SBR.Start
# sequence as earlier successful user CST runs. No PEC.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ProjectRoot,
 [Parameter(Mandatory=$true)][string]$CstBase,
 [Parameter(Mandatory=$true)][string]$FEMSTLRoot,
 [switch]$Quick9
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ci=[Globalization.CultureInfo]::InvariantCulture
$rfRoot=Join-Path $ProjectRoot '03_FEM_TO_CST_RF'
New-Item -ItemType Directory -Path $rfRoot -Force | Out-Null
$log=Join-Path $rfRoot 'CST_RUNS.csv'
if(!(Test-Path $log)){ 'Wind_m_s,AX_deg,AY_deg,Status,NativeTE,NativeTM,Message' | Set-Content $log -Encoding UTF8 }
if(!(Test-Path $CstBase)){throw "CST baseline not found: $CstBase"}
function Invar([double]$v){return $v.ToString('0.############',[Globalization.CultureInfo]::InvariantCulture)}
function CsvQuote([string]$x){return '"'+$x.Replace('"','""')+'"'}
function Record([int]$wind,[double]$x,[double]$y,[string]$status,[string]$te,[string]$tm,[string]$msg){
 $s=@((Invar $wind),(Invar $x),(Invar $y),$status,$te,$tm,$msg) | ForEach-Object {CsvQuote ([string]$_)}
 Add-Content -LiteralPath $log -Value ($s -join ',') -Encoding UTF8
}
function GeometryMacro([string]$folder,[int]$wind,[double]$ax,[double]$ay){
 $solids=@('Core_Left','Core_Right','Zinc_Front_Left','Zinc_Front_Right','Zinc_Back_Left','Zinc_Back_Right')
 $b=[Collections.Generic.List[string]]::new()
 foreach($n in $solids){$b.Add('With Solid');$b.Add(' .Delete "PASSBRIDGE:'+$n+'"');$b.Add('End With')}
 foreach($side in @('Left','Right')){
  foreach($l in @('Core','ZincFront','ZincBack')){
   $name=switch($l){'Core'{"Core_$side"};'ZincFront'{"Zinc_Front_$side"};'ZincBack'{"Zinc_Back_$side"}}
   $path=Join-Path $folder "FEM_W$($wind)_${l}_${side}.stl"
   if(!(Test-Path $path)){throw "Missing finite metal STL: $path"}
   $b.Add('With STL');$b.Add(' .Reset');$b.Add(' .FileName ("'+$path+'")');$b.Add(' .Name ("'+$name+'")');$b.Add(' .Component ("PASSBRIDGE")');$b.Add(' .ImportFileUnits "mm"');$b.Add(' .ScaleToUnit (True)');$b.Add(' .ImportToActiveCoordinateSystem (False)');$b.Add(' .Read');$b.Add('End With')
  }
 }
 foreach($n in $solids){
  $mat=if($n.StartsWith('Core')){'PASSBRIDGE_DX51D_PROVISIONAL'}else{'PASSBRIDGE_Zinc'}
  $b.Add('With Solid');$b.Add(' .ChangeMaterial "PASSBRIDGE:'+$n+'", "'+$mat+'"');$b.Add('End With')
 }
 foreach($axis in @('X','Y')){
  $deg=if($axis -eq 'X'){$ax}else{$ay}
  if ([math]::Abs($deg) -lt 1e-9) { continue }
  $ang=if($axis -eq 'X'){(Invar $deg)+', 0, 0'}else{'0, '+(Invar $deg)+', 0'}
  $triple=if($axis -eq 'X'){ @((Invar $deg),'0','0') }else{ @('0',(Invar $deg),'0') }
  foreach($n in $solids){
   $b.Add('With Transform');$b.Add(' .Reset');$b.Add(' .Name "PASSBRIDGE:'+$n+'"');$b.Add(' .Origin "Free"');$b.Add(' .Center "0", "0", "0"')
   $b.Add(' .Angle "'+$triple[0]+'", "'+$triple[1]+'", "'+$triple[2]+'"');$b.Add(' .MultipleObjects "False"');$b.Add(' .GroupObjects "False"');$b.Add(' .Repetitions "1"');$b.Add(' .MultipleSelection "False"');$b.Add(' .AutoDestination "True"');$b.Add(' .Transform "Shape", "Rotate"');$b.Add('End With')
  }
 }
 return ($b -join "`r`n")
}
$angles=if($Quick9){@(0.0,-0.2,0.2)}else{@(0.0,-0.1,0.1,-0.2,0.2)}
$anyFailed=$false; $count=0; $failureStreak=0
foreach($wind in @(15,25,35)){
 $folder=Join-Path $FEMSTLRoot "W$wind"
 $man=Join-Path $folder 'FEM_GEOMETRY_MANIFEST.json'
 if(!(Test-Path $man)){ Write-Warning "Skipped W$wind because true FEM geometry is missing"; $anyFailed=$true; continue }
 foreach($ax in $angles){foreach($ay in $angles){
  $xTag=(Invar $ax).Replace('-','m').Replace('.','p');$yTag=(Invar $ay).Replace('-','m').Replace('.','p')
  $tag="FEM_W${wind}_X${xTag}_Y${yTag}"
  $caseDir=Join-Path $rfRoot $tag
  $native=Join-Path $caseDir 'NATIVE';$te=Join-Path $native 'TE.txt';$tm=Join-Path $native 'TM.txt'
  if((Test-Path $te) -and (Test-Path $tm) -and (Get-Item $te).Length -gt 200 -and (Get-Item $tm).Length -gt 200){Write-Host "REUSE $tag";continue}
  New-Item -ItemType Directory -Path $caseDir,$native -Force | Out-Null
  $project=Join-Path $rfRoot "$tag.cst"
  $app=$null;$model=$null;$startOk=$false
  try{
   Copy-Item -LiteralPath $CstBase -Destination $project -Force
   $app=New-Object -ComObject CSTStudio.Application
   $null=$app.OpenFile($project)
   $model=$app.Active3D();if($null -eq $model){throw 'Active3D missing; cannot create CST model'}
   $macro=GeometryMacro $folder $wind $ax $ay
   $h=$model.AddToHistory("PASSBRIDGE TRUE FEM wind=$wind AX=$ax AY=$ay",$macro)
   if(-not $h){throw 'CST AddToHistory rejected FEM STL or rotation commands'}
   if(-not $model.Rebuild()){throw 'CST model rebuild failed'}
   $solid=$model.Solid()
   foreach($nm in @('Core_Left','Core_Right','Zinc_Front_Left','Zinc_Front_Right','Zinc_Back_Left','Zinc_Back_Right')){
     $vol=[double]$solid.GetVolume("PASSBRIDGE:$nm")
     if($vol -le 0){throw "Bad volume for $nm ($vol)"}
   }
   $model.Save()
   $as=$model.AsymptoticSolver();$as.SetSolverType('SBR');$as.SetSolverMode('BISTATIC_SCATTERING')
   $as.SetAccuracyLevel('CUSTOM');$as.ResetPolarizations();$as.AddCustomPolarization(0,0,0,1);$as.AddCustomPolarization(1,0,0,0)
   $as.SetSolverMaximumNumberOfReflections(1);$as.SetSolverIncludeMetallicEdgeDiffraction($true)
   $as.SetSolverRayDensityPerLambda(20);$as.ResetFrequencyList();$as.AddFrequencySweep(5.5,5.5,0)
   $as.ResetExcitationAngleList();$as.AddExcitationAngleSweep('POINT',45,45,0,180,180,0)
   $as.ResetObservationAngleList();$as.AddObservationAngleSweep('THETA',40,50,0.05,0,0,0)
   $as.SetSolverStoreResultsAsTablesOnly($true)
   $startOk=$as.Start();if(-not $startOk){throw "CST solver Start=$startOk"}
   $model.Save()
   $far=Join-Path $caseDir 'Export\Farfield'
   $inpTE=Join-Path $far 'farfield_Etheta=(0,0),Ephi=(0,1).txt'
   $inpTM=Join-Path $far 'farfield_Etheta=(1,0),Ephi=(0,0).txt'
   if(!(Test-Path $inpTE) -or !(Test-Path $inpTM)){throw "Missing native CST fields after solver Start; see $far"}
   Copy-Item $inpTE $te -Force;Copy-Item $inpTM $tm -Force
   if((Get-Item $te).Length -le 200 -or (Get-Item $tm).Length -le 200){throw 'Native fields too small'}
   Record $wind $ax $ay 'SOLVED' $te $tm 'CST native scattered field verified'
   Write-Host "SOLVED $tag";$count++;$failureStreak=0
  }catch{
   $anyFailed=$true; $err=$_.Exception.ToString()
   $err | Set-Content -LiteralPath (Join-Path $caseDir 'ERROR.txt') -Encoding UTF8
   Record $wind $ax $ay 'ERROR' '' '' $err
   Write-Warning "CST FAILED $tag : $($_.Exception.Message)"; $failureStreak++
  }finally{
   if($null -ne $model){try{$model.Quit()}catch{}}
   if($null -ne $app){try{$app.Quit()}catch{}}
   [GC]::Collect()
  }
  if($failureStreak -ge 2){Write-Error "Two consecutive CST case failures. Aborting remaining runs; correct the first logged root cause, then rerun (successful cases are preserved).";exit 3}
 }}
}
Write-Host "CST stage ended: newly solved $count; log: $log"
if($anyFailed){exit 2}
