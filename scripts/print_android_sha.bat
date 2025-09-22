@echo off
setlocal enableextensions

REM --- Try to locate keytool ---
set "KEYTOOL=keytool"
where %KEYTOOL% >nul 2>&1
if errorlevel 1 (
  if exist "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" (
    set "KEYTOOL=C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
  ) else (
    echo [WARN] keytool bulunamadi. Java/JDK veya Android Studio ^(JBR^) kurulu mu?
    echo PATH'e keytool ekleyin ya da scriptte KEYTOOL yolunu duzeltin.
  )
)

echo Using keytool: %KEYTOOL%
echo.
echo === Debug keystore (androiddebugkey) SHA-1 / SHA-256 ===
"%KEYTOOL%" -list -v -alias androiddebugkey -keystore "%USERPROFILE%\.android\debug.keystore" -storepass android -keypass android
if errorlevel 1 (
  echo [ERROR] Debug keystore okunamadi. Dosya yoksa once bir debug build calistirin (flutter run) ve tekrar deneyin.
)

echo.
echo === Release keystore (fotojeolog) SHA-1 / SHA-256 ===
"%KEYTOOL%" -list -v -keystore "android\keystore\fotojeolog.keystore" -alias fotojeolog -storepass 194162328296 -keypass 194162328296
if errorlevel 1 (
  echo [WARN] Release keystore okunamadi. Yol/alias/sifreyi kontrol edin ^(android\key.properties^).
)

echo.
echo Bitti. Yukaridaki SHA-1 ve SHA-256 degerlerini Firebase Console'a ekleyin ve yeni google-services.json'u indirin.
endlocal
