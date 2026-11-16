param(
    [Parameter(Mandatory=$true)][string]$DeviceId,
    [ValidateSet('Both','Flutter','Maestro')][string]$Suite='Both',
    [ValidateSet('JT','DietFeatures')][string]$FeatureSet='JT',
    [string]$MaestroPath='maestro',
    [string]$AdbPath="$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repoRoot
$env:MAESTRO_CLI_NO_ANALYTICS='true'
$env:MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED='true'
$env:MAESTRO_DRIVER_STARTUP_TIMEOUT='60000'
if (-not $env:JAVA_HOME -and (Test-Path 'C:\Program Files\Android\Android Studio\jbr')) {
    $env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
}
$env:PATH="$(Split-Path $AdbPath -Parent);$env:JAVA_HOME\bin;$env:PATH"
$env:ANDROID_HOME=Split-Path (Split-Path $AdbPath -Parent) -Parent
$resultDir=Join-Path $repoRoot ('build\e2e\'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
function Assert-Exit([string]$Step) { if($LASTEXITCODE -ne 0) { throw "$Step failed (exit $LASTEXITCODE). See $resultDir" } }
& $AdbPath -s $DeviceId get-state
Assert-Exit 'Device connection'
if($Suite -in @('Both','Flutter')) {
    $target=if($FeatureSet -eq 'DietFeatures') {'integration_test/diet_features_test.dart'} else {'integration_test/jt_flows_test.dart'}
    & flutter test $target -d $DeviceId --dart-define=E2E_TESTING=true --reporter expanded 2>&1 | Tee-Object -FilePath (Join-Path $resultDir 'flutter-integration.log')
    Assert-Exit 'Flutter integration tests'
}
if($Suite -in @('Both','Maestro')) {
    $multiFood=if($FeatureSet -eq 'DietFeatures') {'true'} else {'false'}
    & flutter build apk --debug -t tool/e2e_app.dart --dart-define=E2E_TESTING=true --dart-define=E2E_MULTI_FOOD=$multiFood 2>&1 | Tee-Object -FilePath (Join-Path $resultDir 'maestro-build.log')
    Assert-Exit 'Maestro demo APK build'
    $apk=Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    $appId='com.physical_treatment_and_health_support_system.tarumt.physical_treatment_and_health_support_system.e2e'
    # Verify the build flag actually produced the separate package before installing or clearing data.
    $sdkDir=Split-Path (Split-Path $AdbPath -Parent) -Parent
    $aapt=Get-ChildItem -LiteralPath (Join-Path $sdkDir 'build-tools') -Directory |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if(-not $aapt) { throw 'Android aapt is needed to verify the isolated package.' }
    $badging=& $aapt dump badging $apk
    Assert-Exit 'APK manifest inspection'
    if(-not ($badging | Select-String -SimpleMatch "package: name='$appId'")) { throw 'Refusing to install: APK is not the isolated .e2e package.' }
    & $AdbPath -s $DeviceId install -r $apk
    Assert-Exit 'Isolated APK installation'
    $flows=if($FeatureSet -eq 'DietFeatures') {@('.maestro/flows/10_diet_review.yaml','.maestro/flows/11_multi_food.yaml')} else {@('.maestro/flows/01_profile.yaml','.maestro/flows/02_tracking.yaml','.maestro/flows/03_health_report.yaml','.maestro/flows/04_health_diet_alerts.yaml','.maestro/flows/05_meal_logging.yaml','.maestro/flows/06_diet_plans.yaml','.maestro/flows/07_photo_review.yaml','.maestro/flows/08_login.yaml','.maestro/flows/09_manual_plan.yaml')}
    & $MaestroPath --device $DeviceId test @flows --driver-host-port 7001 --format JUNIT --output (Join-Path $resultDir 'maestro.xml') --test-output-dir (Join-Path $resultDir 'maestro') 2>&1 | Tee-Object -FilePath (Join-Path $resultDir 'maestro.log')
    Assert-Exit 'Maestro flows'
}
Write-Output "Results: $resultDir"
