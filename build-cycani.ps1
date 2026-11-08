param(
 [Parameter(Mandatory=$true)][string]$FlutterSdk,
 [ValidateSet('windows','android')][string]$Target='android'
)
$ErrorActionPreference='Stop'
$flutter=Join-Path ([IO.Path]::GetFullPath($FlutterSdk)) 'bin\flutter.bat'
if(-not (Test-Path -LiteralPath $flutter)){throw 'FlutterSdk 目录下没有 bin\flutter.bat'}
$env:PUB_HOSTED_URL='https://pub.dev'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.googleapis.com'
$buildArgs=@('--release','--no-pub')
Push-Location $PSScriptRoot
try {
 & $flutter pub get
 if($LASTEXITCODE -ne 0){throw '依赖解析失败'}
 & $flutter test --no-pub
 if($LASTEXITCODE -ne 0){throw '自动测试未通过'}
 if($Target -eq 'android'){& $flutter build apk @buildArgs --target-platform android-arm64}
 else {& $flutter build windows @buildArgs}
 if($LASTEXITCODE -ne 0){throw '构建失败'}
} finally {Pop-Location}
