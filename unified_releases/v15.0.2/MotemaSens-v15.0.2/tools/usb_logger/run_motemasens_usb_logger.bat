@echo off
setlocal
title MotemaSens USB Logger
cd /d "%~dp0"

set "PYLAUNCH=py -3"
%PYLAUNCH% --version >nul 2>&1
if errorlevel 1 (
  set "PYLAUNCH=python"
  %PYLAUNCH% --version >nul 2>&1
)

if errorlevel 1 (
  echo Python was not found on this PC.
  echo Trying to install Python 3 using winget...
  where winget >nul 2>&1
  if errorlevel 1 (
    echo.
    echo winget is not available. Please install Python 3.11 or newer from:
    echo https://www.python.org/downloads/windows/
    pause
    exit /b 1
  )
  winget install -e --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
  set "PYLAUNCH=py -3"
  %PYLAUNCH% --version >nul 2>&1
  if errorlevel 1 (
    set "PYLAUNCH=python"
    %PYLAUNCH% --version >nul 2>&1
  )
)

%PYLAUNCH% -m pip --version >nul 2>&1
if errorlevel 1 (
  echo Installing pip...
  %PYLAUNCH% -m ensurepip --upgrade
)

echo Checking MotemaSens USB Logger prerequisites...
%PYLAUNCH% -m pip install --upgrade pip pyserial
if errorlevel 1 (
  echo.
  echo Failed to install Python packages. Check internet access and try again.
  pause
  exit /b 1
)

echo Starting MotemaSens USB Logger...
%PYLAUNCH% "%~dp0motemasens_usb_logger.py"
if errorlevel 1 (
  echo.
  echo MotemaSens USB Logger closed with an error.
  pause
  exit /b 1
)

endlocal
