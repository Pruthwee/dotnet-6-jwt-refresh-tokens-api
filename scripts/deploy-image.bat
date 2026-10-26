@echo off
setlocal enabledelayedexpansion

REM Deploy script for Azure AKS
REM Usage: scripts\deploy-image.bat

set "PROJECT_NAME=dotnet_jwt_mcont2_1929"
for /f %%i in ('powershell -NoProfile -Command "(('%PROJECT_NAME%').ToLower() -creplacing '[^a-z0-9]', '-').Trim('-')"') do set "IMAGE_NAME=%%i"

echo === Azure AKS Deployment ===

set /p RESOURCE_GROUP="Enter Azure resource group: "
set /p CLUSTER_NAME="Enter AKS cluster name: "
set /p IMAGE_URI="Enter full image URI (registry/repo:tag): "

echo.
echo Enter values for the application's environment variables.
echo Press Enter to skip (use default or leave unset).
echo.

set /p APPSETTINGS_SECRET="Enter value for AppSettings__Secret (or press Enter to skip): "

echo.
echo === Configuring kubectl for AKS cluster ===
az aks get-credentials --resource-group "%RESOURCE_GROUP%" --name "%CLUSTER_NAME%"
if !ERRORLEVEL! neq 0 (
    echo Failed to configure kubectl for AKS cluster
    exit /b 1
)

kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo Failed to connect to cluster
    exit /b 1
)

echo.
echo === Creating namespace ===
kubectl apply -f kubernetes\namespace.yaml

echo.
echo === Creating Kubernetes Secret ===
set "SECRET_CREATED=0"
if not "%APPSETTINGS_SECRET%"=="" (
    kubectl create secret generic !IMAGE_NAME!-secrets -n !IMAGE_NAME! --from-literal=appsettings-secret="%APPSETTINGS_SECRET%" --dry-run=client -o yaml | kubectl apply -f -
    if !ERRORLEVEL! neq 0 (
        echo Failed to create Kubernetes Secret
        exit /b 1
    )
    set "SECRET_CREATED=1"
) else (
    echo No credentials provided. Skipping Secret creation.
    echo You may need to create the secret manually before deploying.
)

echo.
echo === Deploying application ===

REM Replace placeholders in deployment.yaml
powershell -NoProfile -Command "(Get-Content kubernetes\deployment.yaml) -replace '{{IMAGE_URI}}', '%IMAGE_URI%' | Set-Content kubernetes\deployment.yaml"
powershell -NoProfile -Command "(Get-Content kubernetes\deployment.yaml) -replace '{{NAMESPACE}}', '!IMAGE_NAME!' | Set-Content kubernetes\deployment.yaml"

kubectl apply -f kubernetes\deployment.yaml
if !ERRORLEVEL! neq 0 (
    echo Failed to apply deployment
    exit /b 1
)

kubectl apply -f kubernetes\service.yaml
if !ERRORLEVEL! neq 0 (
    echo Failed to apply service
    exit /b 1
)

kubectl apply -f kubernetes\ingress.yaml
if !ERRORLEVEL! neq 0 (
    echo Failed to apply ingress
    exit /b 1
)

echo.
echo === Waiting for rollout ===
kubectl rollout status deployment\!IMAGE_NAME! -n !IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
    echo Rollout failed
    echo To rollback: kubectl rollout undo deployment\!IMAGE_NAME! -n !IMAGE_NAME!
    exit /b 1
)

echo.
echo === Deployment status ===
kubectl get pods,svc,ingress -n !IMAGE_NAME!

echo.
echo === Application URL ===
echo Application URL: https://!IMAGE_NAME!.example.com ^(may take a moment to become available^)

echo.
echo === Deployment complete ===
echo To rollback on failure: kubectl rollout undo deployment\!IMAGE_NAME! -n !IMAGE_NAME!
