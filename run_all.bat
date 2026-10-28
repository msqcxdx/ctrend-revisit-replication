@REM CTREND_REVISIT_FILE_PURPOSE: Forward Windows users to the Linux/WSL production entry point without duplicating orchestration logic.
@echo off
where bash >nul 2>nul
if errorlevel 1 (
  echo Production requires Linux bash, setsid and flock. Use Linux or WSL.
  exit /b 2
)
bash "%~dp0run_all.sh" %*
exit /b %errorlevel%
