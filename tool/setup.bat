@echo off
rem Windows: Android iskeletini kurar, bagimliliklari indirir, kodu uretir.
cd /d "%~dp0.."

if not exist android (
  if exist "%TEMP%\kocum_scaffold" rmdir /s /q "%TEMP%\kocum_scaffold"
  call flutter create --org com.kocum --project-name kocum --platforms android "%TEMP%\kocum_scaffold\kocum"
  if errorlevel 1 goto fail
  xcopy /E /I /Y "%TEMP%\kocum_scaffold\kocum\android" "android" >nul
)

call flutter pub get
if errorlevel 1 goto fail
call dart tool\patch_android.dart
if errorlevel 1 goto fail
call dart run build_runner build --delete-conflicting-outputs
if errorlevel 1 goto fail

echo.
echo Hazir. Telefonu USB ile bagla ve su komutu calistir:  flutter run --release
exit /b 0

:fail
echo.
echo Bir adim basarisiz oldu. Yukaridaki hata mesajini kopyalayip bana gonder.
exit /b 1
