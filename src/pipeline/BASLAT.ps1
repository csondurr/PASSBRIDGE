# PASSBRIDGE: COMSOL structural refinement -> REAL FEM u,v,w -> CST SBR -> MATLAB OFDM.
# Tested components: Python geometry/summary on controlled mock data, previous COMSOL source
# comes from a user-supplied successfully executed 9-case COMSOL batch.
# CST/COMSOL/MATLAB cannot be executed by the author on the user's Windows machine.
[CmdletBinding()]
param([switch]$UseExistingMeshOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$desktop=[Environment]::GetFolderPath('Desktop')
$root=Join-Path $desktop 'PASSBRIDGE_FINAL\DIGITAL_TWIN_FINAL'
$fem=Join-Path $desktop 'PASSBRIDGE_COMSOL_FINAL\TAM_PANEL_FEM'
$old=Join-Path $desktop 'PASSBRIDGE_FINAL'
New-Item -ItemType Directory -Path $root,$(Join-Path $root '01_CHECK'),$(Join-Path $root '02_FEM_REFINEMENT'),$(Join-Path $root '03_FEM_STL'),$(Join-Path $root '04_LINK'),$(Join-Path $root '05_MATLAB_OFDM'),$(Join-Path $root '06_RAPOR') -Force | Out-Null
$pipelineLog=Join-Path $root '01_CHECK\PIPELINE_LOG.txt'
$statusCsv=Join-Path $root '01_CHECK\PIPELINE_STAGES.csv'
if(!(Test-Path $statusCsv)){'Stage,Status,Details'|Set-Content -LiteralPath $statusCsv -Encoding UTF8}
function Note([string]$str){$s="$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $str";Write-Host $s;Add-Content -LiteralPath $pipelineLog -Value $s -Encoding UTF8}
function Stage([string]$id,[string]$state,[string]$info){
 $safe=$info.Replace('"','''').Replace(',',';').Replace("`r",' ').Replace("`n",' ')
 Add-Content -LiteralPath $statusCsv -Value "`"$id`",`"$state`",`"$safe`"" -Encoding UTF8
 Note "$id : $state : $safe"
}
$pyexe=$null;$pyprefix=@()
function Py([string]$file,[string[]]$extra){
 if(!$script:pyexe){throw 'Python not available'}
 $pyArgs=@();$pyArgs+=@($script:pyprefix);$pyArgs+=$file;$pyArgs+=@($extra)
 & $script:pyexe @pyArgs
 if($LASTEXITCODE -ne 0){throw "Python script failed ($LASTEXITCODE): $file"}
}
function ExportRefined([string]$runlog,[string]$dest,[string]$femRoot){
 $items=@();if(!(Test-Path $runlog)){return 0}
 foreach($line in Get-Content -LiteralPath $runlog){
  if($line -match 'CASE_OK\|4\|(15|25|35)\|([\d.]+)\|([\d.]+)\|([\d.]+)\|(G1_MESH4_W\d+\.mph)'){
    $m=4;$v=$Matches[1];$p=$Matches[2];$d=$Matches[3];$stress=$Matches[4];$project=$Matches[5]
    $mph=Join-Path $femRoot $project; $uvw=Join-Path $femRoot $project.Replace('.mph','_DISPLACEMENT.txt')
    if((Test-Path $mph) -and (Get-Item $mph).Length -gt 1024 -and (Test-Path $uvw) -and (Get-Item $uvw).Length -gt 1024){
      $items += [pscustomobject]@{mesh_size=$m;windspeed_m_s=$v;pressure_Pa=$p;max_displacement_mm=$d;max_mises_MPa=$stress;solver_status='SOLVED_EXPORTED';project_file=$project}
    }
  }
 }
 if($items.Count){$items|Export-Csv -LiteralPath $dest -Encoding UTF8 -NoTypeInformation}
 return $items.Count
}
function TryRefine(){
 $src=Join-Path $PSScriptRoot 'PASSBRIDGE_G1_FEM.java'
 if(!(Test-Path $src)){ Stage 'COMSOL_REFINE' 'SKIPPED' 'Working Java source not bundled';return }
 $csv=Join-Path $root '02_FEM_REFINEMENT\REFINED_FEM_RESULTS.csv'
 if((Test-Path $csv) -and (Import-Csv $csv).Count -ge 3){Stage 'COMSOL_REFINE' 'REUSED' 'Mesh4 refined results already exist';return}
 $bin='C:\Program Files\COMSOL\COMSOL64\Multiphysics\bin\win64'
 $cc=Join-Path $bin 'comsolcompile.exe';$bb=Join-Path $bin 'comsolbatch.exe'
 if(!(Test-Path $cc) -or !(Test-Path $bb)){Stage 'COMSOL_REFINE' 'SKIPPED' 'COMSOL 6.4 compile/batch not found';return}
 if(Get-Process comsolbatch -ErrorAction SilentlyContinue){Stage 'COMSOL_REFINE' 'SKIPPED' 'Another COMSOL batch is active';return}
 $work=Join-Path $root '02_FEM_REFINEMENT\JAVA_BUILD';New-Item -ItemType Directory -Path $work -Force | Out-Null
 $file=Join-Path $work 'PASSBRIDGE_REFINE4.java'
 $code=[IO.File]::ReadAllText($src,[Text.Encoding]::UTF8)
 foreach($pair in @(@('public class PASSBRIDGE_G1_FEM','public class PASSBRIDGE_REFINE4'),@('new int[]{7,6,5}','new int[]{4}'),@('PASSBRIDGE_G1_GEOMETRY.mph','PASSBRIDGE_REFINE4_GEOMETRY.mph'),@('PASSBRIDGE_G1_PHYSICS.mph','PASSBRIDGE_REFINE4_PHYSICS.mph'),@('PASSBRIDGE_G1_FINAL_STRUCTURAL.mph','PASSBRIDGE_REFINE4_FINAL_STRUCTURAL.mph'))){
  if(!$code.Contains($pair[0])){throw "Cannot patch known working COMSOL source: missing $($pair[0])"}
  $code=$code.Replace($pair[0],$pair[1])
 }
 if(!$code.Contains('__PASSBRIDGE_OUT_DIR__')){throw 'Working Java source has unexpected directory placeholder'}
 $code=$code.Replace('__PASSBRIDGE_OUT_DIR__',$fem.Replace('\','/'))
 [IO.File]::WriteAllText($file,$code,[Text.UTF8Encoding]::new($false))
 $co=Join-Path $root '02_FEM_REFINEMENT\COMPILE_STDOUT.txt';$ce=Join-Path $root '02_FEM_REFINEMENT\COMPILE_STDERR.txt'
 Note 'COMSOL: compile additional mesh4 from known previously successful Java source'
 $proc=Start-Process -FilePath $cc -WorkingDirectory $work -ArgumentList @('"'+$file+'"') -Wait -PassThru -RedirectStandardOutput $co -RedirectStandardError $ce
 if($proc.ExitCode -ne 0){Stage 'COMSOL_REFINE' 'FAILED_NONBLOCKING' "Java compile exit $($proc.ExitCode); see $ce";return}
 $clazz=Join-Path $work 'PASSBRIDGE_REFINE4.class'
 if(!(Test-Path $clazz)){Stage 'COMSOL_REFINE' 'FAILED_NONBLOCKING' 'Class not created';return}
 $ro=Join-Path $root '02_FEM_REFINEMENT\COMSOL_REFINEMENT_LOG.txt';$re=Join-Path $root '02_FEM_REFINEMENT\COMSOL_REFINEMENT_STDERR.txt'
 $proc=Start-Process -FilePath $bb -WorkingDirectory $work -ArgumentList @('-inputfile',('"'+$clazz+'"'),'-np','2') -Wait -PassThru -RedirectStandardOutput $ro -RedirectStandardError $re
 $n=ExportRefined $ro $csv $fem
 if($proc.ExitCode -ne 0 -or $n -ne 3){Stage 'COMSOL_REFINE' 'FAILED_NONBLOCKING' "Exit=$($proc.ExitCode); verified $n/3 saved mph+uvw"}
 else{Stage 'COMSOL_REFINE' 'SOLVED' 'New mesh4 15/25/35 m/s mph files and UVW exports verified'}
}
function PackResults(){
 $work=Join-Path $root '07_UPLOAD_SUMMARY';New-Item -ItemType Directory -Path $work -Force|Out-Null
 $toCopy=@('01_CHECK\PIPELINE_LOG.txt','01_CHECK\PIPELINE_STAGES.csv','02_FEM_REFINEMENT\REFINED_FEM_RESULTS.csv', '02_FEM_REFINEMENT\COMSOL_REFINEMENT_LOG.txt','04_LINK\LINK_CASES.csv','04_LINK\WORST_CASES.csv','04_LINK\RF_VALIDATION.json','05_MATLAB_OFDM\MATLAB_OFDM_RESULTS.csv','05_MATLAB_OFDM\OFDM_THROUGHPUT.png','05_MATLAB_OFDM\OFDM_SNR.png','05_MATLAB_OFDM\SIMULATION_ASSUMPTIONS.txt','06_RAPOR\PASSBRIDGE_DIGITAL_FINAL.md','06_RAPOR\PASSBRIDGE_DIGITAL_FINAL.html','06_RAPOR\MESH_QA.csv','06_RAPOR\FINAL_STATUS.json','03_FEM_TO_CST_RF\CST_RUNS.csv','01_CHECK\CST_STDOUT.txt','01_CHECK\CST_STDERR.txt','02_FEM_REFINEMENT\COMPILE_STDERR.txt','02_FEM_REFINEMENT\COMSOL_REFINEMENT_STDERR.txt','05_MATLAB_OFDM\MATLAB_STDOUT.txt','05_MATLAB_OFDM\MATLAB_STDERR.txt')
 foreach($f in $toCopy){$src=Join-Path $root $f;if(Test-Path $src){$dest=Join-Path $work ([IO.Path]::GetFileName($f));Copy-Item -LiteralPath $src -Destination $dest -Force}}
 $destzip=Join-Path $root 'PASSBRIDGE_DIJITAL_SISTEM_SONUCLAR.zip'
 if(Test-Path $destzip){Remove-Item $destzip -Force}
 $files=Get-ChildItem $work -File
 if($files.Count){Compress-Archive -Path (Join-Path $work '*') -DestinationPath $destzip -Force}
 Note "User upload bundle: $destzip"
}
$success=$false
try{
 Note 'PASSBRIDGE integral FEM -> CST -> MATLAB pipeline started. Real native data required.'
 # Preflight
 if(!(Test-Path (Join-Path $fem 'FEM_RESULTS.csv'))){throw "Previous real FEM data missing: $fem\FEM_RESULTS.csv"}
 foreach($v in (15,25,35)){
  $source=Join-Path $fem "G1_MESH5_W${v}_DISPLACEMENT.txt"
  if(!(Test-Path $source)){throw "COMSOL displacement field missing: $source. Do not substitute synthetic bends."}
 }
 $cand=@((Join-Path $old '01_MASTER_MODEL\PASSBRIDGE_FINAL_MASTER.cst'),(Join-Path $old 'PASSBRIDGE_FINAL_MASTER.cst'))
 $cst=$null;foreach($f in $cand){if(Test-Path $f){$cst=$f;break}}
 if(!$cst){throw "Verified CST baseline missing. Expected $($cand -join ' OR ')"}
 $cmd=Get-Command python -ErrorAction SilentlyContinue
 if($cmd){$pyexe=$cmd.Source}
 else{$cmd=Get-Command py -ErrorAction SilentlyContinue;if($cmd){$pyexe=$cmd.Source;$pyprefix=@('-3')}}
 if(!$pyexe){throw 'Python 3.10+ is required; earlier CST recovery already used Python. No synthetic fallback.'}
 & $pyexe @pyprefix -c 'import sys; assert sys.version_info>=(3,10)' 
 if($LASTEXITCODE -ne 0){throw 'Python 3.10+ check failed'}
 Stage 'PREFLIGHT' 'PASS' "FEM CSV and 3 displacement exports found, CST=$cst, Python=$pyexe"
 if(-not $UseExistingMeshOnly){TryRefine}else{Stage 'COMSOL_REFINE' 'OPTIONAL_SKIPPED' 'Used previously solved mesh5'}
 $refined=Join-Path $root '02_FEM_REFINEMENT\REFINED_FEM_RESULTS.csv'
 $refinedRows=@();if(Test-Path $refined){$refinedRows=@(Import-Csv $refined)}
 foreach($wind in @(15,25,35)){
  # Use best available higher-resolution real field. Do not invent field if refinement fails.
  $latest=Join-Path $fem "G1_MESH4_W${wind}_DISPLACEMENT.txt"
  $mesh=5
  if((Test-Path $latest) -and ((Get-Item $latest).Length -gt 1024) -and (@($refinedRows|Where-Object{[int]$_.windspeed_m_s -eq $wind}).Count -eq 1)){$mesh=4}
  else{$latest=Join-Path $fem "G1_MESH5_W${wind}_DISPLACEMENT.txt"}
  $out=Join-Path $root "03_FEM_STL\W$wind"
  $man=Join-Path $out 'FEM_GEOMETRY_MANIFEST.json'
  if(Test-Path $man){
   $j=Get-Content -LiteralPath $man -Raw|ConvertFrom-Json
   if($j.source_FEM_file -eq $latest -and (Test-Path (Join-Path $out "FEM_W${wind}_Core_Left.stl"))){Stage "FEM_STL_W$wind" 'REUSED' "Previously interpolated real FEM mesh$mesh";continue}
  }
  Stage "FEM_STL_W$wind" 'RUNNING' "True COMSOL u,v,w mesh$mesh"
  Py (Join-Path $PSScriptRoot 'FEMDEN_STL.py') @('--input',$latest,'--out',$out,'--wind',"$wind",'--grid','41')
  if(!(Test-Path $man)){throw "FEM -> STL failed: $man missing"}
  Stage "FEM_STL_W$wind" 'PASS' 'Six finite-thickness metal STL solids built from actual FEM field'
 }
 # CST is the only authentic electromagnetic solver for the 2m finite conductivity panel.
 Note 'Starting CST real deformed geometry x 25 tilt pairs x 3 wind cases. Successful results are automatically reused.'
 $cout=Join-Path $root '01_CHECK\CST_STDOUT.txt';$cerr=Join-Path $root '01_CHECK\CST_STDERR.txt'
 $argList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'CST_FEM_RF.ps1')+'"'),'-ProjectRoot',('"'+$root+'"'),'-CstBase',('"'+$cst+'"'),'-FEMSTLRoot',('"'+(Join-Path $root '03_FEM_STL')+'"'))
 $proc=Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Wait -PassThru -RedirectStandardOutput $cout -RedirectStandardError $cerr
 if($proc.ExitCode -ne 0){Stage 'CST_RF' 'PARTIAL' "Exit $($proc.ExitCode). See $cout / $cerr and first error file"}
 Py (Join-Path $PSScriptRoot 'DOGRULA_RCS.py') @('--root',$root,'--complete')
 Stage 'CST_RF' 'PASS' '150 real native TE/TM cases from FEM-coupled geometries verified'
 $matlab=(Get-Command matlab -ErrorAction SilentlyContinue)
 if($matlab){$mat=$matlab.Source}else{$mat='C:\Program Files\MATLAB\R2025b\bin\matlab.exe'}
 if(!(Test-Path $mat)){throw "MATLAB executable not found: $mat. RF results are preserved."}
 $mfile=Join-Path $root '05_MATLAB_OFDM\MATLAB_OFDM.m'
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MATLAB_OFDM.m') -Destination $mfile -Force
 $cmd= "run('" + $mfile.Replace('\','/').Replace("'","''") + "')"
 $mo=Join-Path $root '05_MATLAB_OFDM\MATLAB_STDOUT.txt';$me=Join-Path $root '05_MATLAB_OFDM\MATLAB_STDERR.txt'
 $proc=Start-Process -FilePath $mat -ArgumentList @('-batch',('"'+$cmd+'"')) -Wait -PassThru -RedirectStandardOutput $mo -RedirectStandardError $me
 if($proc.ExitCode -ne 0 -or !(Test-Path (Join-Path $root '05_MATLAB_OFDM\MATLAB_OFDM_RESULTS.csv'))){throw "MATLAB failed exit=$($proc.ExitCode). Inspect $mo and $me. RF results saved."}
 Stage 'MATLAB_OFDM' 'PASS' 'Actual CST link cases simulated with base MATLAB QPSK OFDM, BER, PER, throughput'
 $success=$true
}catch{
 Stage 'PIPELINE' 'BLOCKED' $_.Exception.Message
}finally{
 try{Py (Join-Path $PSScriptRoot 'RAPORLA.py') @('--root',$root,'--fem-root',$fem)}catch{Stage 'REPORT' 'WARNING' $_.Exception.Message}
 try{PackResults}catch{Note "Packaging warning: $($_.Exception.Message)"}
 Note "Digital twin output directory: $root"
 Start-Process explorer.exe $root
}
if(!$success){Write-Host 'A stage could not be completed. Existing real results were preserved; see PIPELINE_STAGES.csv.';exit 2}
Write-Host 'FEM -> CST -> MATLAB numerical simulation chain completed. Check mesh QA and assumptions in FINAL_STATUS.json.'
