@echo off
REM Inno Setup SignTool entrypoint. Invoked as: sign-file.cmd <path-to-sign>
REM Keeps quoting simple so ISCC does not mangle PowerShell -File paths.
setlocal
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sign-file.ps1" %*
exit /b %ERRORLEVEL%
