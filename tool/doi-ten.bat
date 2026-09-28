@echo off
rem Công cụ nội bộ nhóm SafeFamily.
chcp 65001 >nul
cd /d "%~dp0.."
dart run tool/rename.dart %*
echo.
pause
