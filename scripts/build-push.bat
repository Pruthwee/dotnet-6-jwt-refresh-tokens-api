@echo off
setlocal enabledelayedexpansion

REM Build and push script for Azure ACR
REM Usage: scripts\build-push.bat

set "PROJECT_NAME=dotnet_jwt_mcont2_1929"

REM Sanitize project name to a valid image name (lowercase, hyphens)
set "IMAGE_NAME=%PROJECT_NAME%"
set "IMAGE_NAME=%IMAGE_NAME:a=a%"
REM Convert to lowercase using PowerShell
for /f %%i in ('powershell -NoProfile -Command "(('%PROJECT_NAME%').ToLower() -creplace '[^a-z0-9]', '-').Trim('-')"') do set "IMAGE_NAME=%%i"

set /p ACR_NAME="Enter Azure ACR name (ACR_NAME): "
set /p IMAGE_TAG="Enter image tag (press Enter for latest): "

if "%IMAGE_TAG%"=="" (
    set "IMAGE_TAG=latest"
)

REM Sanitize tag using PowerShell
for /f %%i in ('powershell -NoProfile -Command "('%IMAGE_TAG%' -creplace '[^a-z0-9._-]', '-').Trim('-')"') do set "IMAGE_TAG=%%i"

set "FULL_IMAGE_NAME=%ACR_NAME%.azurecr.io/%IMAGE_NAME%:%IMAGE_TAG%"

echo === Building Docker image: %FULL_IMAGE_NAME% ===
docker build -f Dockerfile -t "%FULL_IMAGE_NAME%" .
if !ERRORLEVEL! neq 0 (
    echo Docker build failed
    exit /b 1
)

echo === Logging in to Azure ACR: %ACR_NAME% ===
az acr login --name "!ACR_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ACR login failed
    exit /b 1
)

echo === Pushing Docker image: %FULL_IMAGE_NAME% ===
docker push "%FULL_IMAGE_NAME%"
if !ERRORLEVEL! neq 0 (
    echo Docker push failed
    exit /b 1
)

echo === Build and push complete ===
echo Image: %FULL_IMAGE_NAME%
