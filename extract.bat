@echo off
setlocal enabledelayedexpansion

:: Determine script directory
set "SCRIPT_DIR=%~dp0"

:: Check if lune is available in PATH
where lune >nul 2>nul
if %ERRORLEVEL% neq 0 (
    :: Check standard Rokit binary directory
    if exist "%USERPROFILE%\.rokit\bin\lune.exe" (
        set "PATH=%USERPROFILE%\.rokit\bin;%PATH%"
    ) else (
        where rokit >nul 2>nul
        if %ERRORLEVEL% equ 0 (
            echo [INFO] Running 'rokit install' to install managed tools...
            pushd "%SCRIPT_DIR%"
            rokit install
            popd
            if exist "%USERPROFILE%\.rokit\bin\lune.exe" (
                set "PATH=%USERPROFILE%\.rokit\bin;%PATH%"
            )
        )
    )
)

:: Verify lune is now runnable
where lune >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] 'lune' command could not be found. 1>&2
    echo Please ensure Rokit or Lune is installed: 1>&2
    echo   Rokit: https://github.com/rojo-rbx/rokit 1>&2
    echo   Lune:  https://lune-org.github.io/docs/ 1>&2
    exit /b 1
)

:: Execute extract.luau with arguments forwarded
lune run "%SCRIPT_DIR%extract.luau" %*
exit /b %ERRORLEVEL%
