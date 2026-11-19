@echo off
setlocal
setlocal EnableDelayedExpansion

:: Define directories
set BAL_EXAMPLES_DIR=%~dp0
set BAL_CENTRAL_DIR=%USERPROFILE%\.ballerina\repositories\central.ballerina.io
set BAL_HOME_DIR=%BAL_EXAMPLES_DIR%..\ballerina

:: Ensure a command is provided
if "%~1"=="" (
    echo Invalid command provided. Please provide "build" or "run" as the command.
    exit /b 1
)

:: Set the Ballerina command
if "%~1"=="build" (
    set BAL_CMD=build
) else if "%~1"=="run" (
    set BAL_CMD=run
) else (
    echo Invalid command provided: "%~1". Please provide "build" or "run" as the command.
    exit /b 1
)

:: Read Ballerina package name
for /f "tokens=2 delims== " %%A in ('findstr /r "^name" "%BAL_HOME_DIR%\Ballerina.toml"') do (
    set BAL_PACKAGE_NAME=%%~A
    set BAL_PACKAGE_NAME=!BAL_PACKAGE_NAME:"=!"
    set BAL_PACKAGE_NAME=!BAL_PACKAGE_NAME:~0,-1!
)

:: Push the package to the local repository
cd /d "%BAL_HOME_DIR%"
call bal pack
call bal push --repository=local

:: Remove the cache directories in the repositories
for /d %%D in ("%BAL_CENTRAL_DIR%\cache-*") do (
    if exist "%%D" (
        rmdir /s /q "%%D"
    )
)
echo Successfully cleaned the cache directories

:: Create the package directory in the central repository
if not exist "%BAL_CENTRAL_DIR%\bala\ballerinax\%BAL_PACKAGE_NAME%" (
    mkdir "%BAL_CENTRAL_DIR%\bala\ballerinax\%BAL_PACKAGE_NAME%"
)

:: Update the central repository
set BAL_DESTINATION_DIR=%BAL_CENTRAL_DIR%\bala\ballerinax\%BAL_PACKAGE_NAME%
set BAL_SOURCE_DIR=%USERPROFILE%\.ballerina\repositories\local\bala\ballerinax\%BAL_PACKAGE_NAME%
if exist "%BAL_DESTINATION_DIR%" (
    rmdir /s /q "%BAL_DESTINATION_DIR%"
)
if exist "%BAL_SOURCE_DIR%" (
    xcopy /e /i "%BAL_SOURCE_DIR%" "%BAL_DESTINATION_DIR%"
)
echo Successfully updated the local central repositories

echo %BAL_DESTINATION_DIR%
echo %BAL_SOURCE_DIR%

:: Loop through examples in the examples directory
cd /d "%BAL_EXAMPLES_DIR%"
set ERROR_OCCURRED=0
for /d %%D in ("%BAL_EXAMPLES_DIR%\*") do (
    if not "%%~nD"=="build" (
        cd /d "%%D"
        call bal %BAL_CMD%
        if errorlevel 1 (
            set ERROR_OCCURRED=1
        )
        cd ..
    )
)
if %ERROR_OCCURRED%==1 (
    echo An error occurred during the execution of the loop.
    exit /b 1
)

:: Remove generated JAR files
for %%F in ("%BAL_HOME_DIR%\*.jar") do (
    del "%%F"
)
