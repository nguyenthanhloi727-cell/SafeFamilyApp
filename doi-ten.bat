@echo off
rem Bấm đúp để đổi app SafeFamily sang tên thành viên nhóm (xem CONTRIBUTING.md, mục 8).
chcp 65001 >nul
cd /d "%~dp0"
dart run tool/rename.dart %*
echo.
pause
