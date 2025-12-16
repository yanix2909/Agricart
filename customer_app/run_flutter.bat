@echo off
echo AgriCart Customer App - Flutter Runner
echo =====================================
echo.

if "%1"=="clean" (
    echo Cleaning Flutter project...
    flutter clean
) else if "%1"=="get" (
    echo Getting Flutter dependencies...
    flutter pub get
) else if "%1"=="build" (
    echo Building APK with dependency validation skipped...
    flutter build apk --debug --android-skip-build-dependency-validation
) else if "%1"=="run" (
    echo Running Flutter app with dependency validation skipped...
    flutter run --debug --android-skip-build-dependency-validation
) else (
    echo Usage:
    echo   run_flutter.bat clean    - Clean the project
    echo   run_flutter.bat get      - Get dependencies
    echo   run_flutter.bat build    - Build APK
    echo   run_flutter.bat run      - Run the app
    echo.
    echo Note: This script automatically skips Android build dependency validation
    echo to avoid issues with the qr_code_scanner package.
)
