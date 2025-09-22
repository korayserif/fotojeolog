@echo off
setlocal enableextensions
pushd android

if exist gradlew.bat (
  call gradlew.bat --no-daemon signingReport
) else (
  echo [ERROR] gradlew.bat bulunamadı. android klasöründeyken Flutter/Android sync yapmayi deneyin.
)

popd
endlocal
