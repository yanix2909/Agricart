param(
    [Parameter(Position=0)]
    [ValidateSet("clean", "get", "build", "run")]
    [string]$Command = ""
)

Write-Host "AgriCart Customer App - Flutter Runner" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

switch ($Command) {
    "clean" {
        Write-Host "Cleaning Flutter project..." -ForegroundColor Yellow
        flutter clean
    }
    "get" {
        Write-Host "Getting Flutter dependencies..." -ForegroundColor Yellow
        flutter pub get
    }
    "build" {
        Write-Host "Building APK with dependency validation skipped..." -ForegroundColor Yellow
        flutter build apk --debug --android-skip-build-dependency-validation
    }
    "run" {
        Write-Host "Running Flutter app with dependency validation skipped..." -ForegroundColor Yellow
        flutter run --debug --android-skip-build-dependency-validation
    }
    default {
        Write-Host "Usage:" -ForegroundColor Cyan
        Write-Host "  .\run_flutter.ps1 clean    - Clean the project" -ForegroundColor White
        Write-Host "  .\run_flutter.ps1 get      - Get dependencies" -ForegroundColor White
        Write-Host "  .\run_flutter.ps1 build    - Build APK" -ForegroundColor White
        Write-Host "  .\run_flutter.ps1 run      - Run the app" -ForegroundColor White
        Write-Host ""
        Write-Host "Note: This script automatically skips Android build dependency validation" -ForegroundColor Yellow
        Write-Host "to avoid issues with the qr_code_scanner package." -ForegroundColor Yellow
    }
}
