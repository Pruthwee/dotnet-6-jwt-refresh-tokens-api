# Deployment Guide — dotnet-jwt-mcont2-1929

## Prerequisites and System Requirements

### Local Development
- **.NET 6.0 SDK** (or later compatible SDK)
- **Docker** (for local container builds and Docker Compose)
- **Docker Compose** (v2 or later)

### Azure AKS Deployment
- **Azure CLI** (`az`) — for ACR login and AKS cluster authentication
- **Docker** — for building and pushing container images
- **kubectl** — for deploying to and managing the AKS cluster
- An **Azure subscription** with permissions to:
  - Create/read Azure Container Registry (ACR)
  - Create/read Azure Kubernetes Service (AKS) clusters
  - Create/manage Kubernetes resources (Deployments, Services, Ingresses, Secrets)

### Azure Resources Required
- **Azure Container Registry (ACR)** — to store the container image
- **Azure Kubernetes Service (AKS)** cluster with an Application Gateway Ingress Controller (AGIC)
- **Azure Application Gateway** (WAF v2 recommended) with WebSocket support enabled for Blazor Server workloads

---

## Local Setup with Docker Compose

1. Set the required environment variable for the JWT signing secret:

   ```bash
   export AppSettings__Secret="your-secret-key-here"
   ```

2. Build and run the application locally:

   ```bash
   docker-compose up --build
   ```

3. The application will be available at `http://localhost:8080`.

4. Health check endpoint: `http://localhost:8080/health`

5. API endpoints (require JWT authentication): `http://localhost:8080/users`

### Configuration (appsettings.json)

The application reads the following settings from `appsettings.json` and environment variables:

| Setting | Environment Variable | Description |
|---|---|---|
| `AppSettings:Secret` | `AppSettings__Secret` | JWT token signing secret (**required**) |
| `AppSettings:RefreshTokenTTL` | `AppSettings__RefreshTokenTTL` | Refresh token time-to-live in days (default: 2) |

The `AppSettings__Secret` is a credential and must be provided via environment variable or Kubernetes Secret — it is never hardcoded in the container image.

---

## Building and Pushing to Azure ACR

### Using the shell script (Linux/macOS):

```bash
./scripts/build-push.sh
```

The script will prompt for:
1. **Azure ACR name** — your Azure Container Registry name
2. **Image tag** — press Enter for `latest`

It will:
- Build the Docker image using the multi-stage Dockerfile
- Log in to your Azure ACR via `az acr login`
- Push the image to `<acr-name>.azurecr.io/dotnet-jwt-mcont2-1929:<tag>`

### Using the batch script (Windows):

```cmd
scripts\build-push.bat
```

---

## Deploying to Azure AKS

### Using the shell script (Linux/macOS):

```bash
./scripts/deploy-image.sh
```

The script will prompt for:
1. **Azure resource group** — the resource group containing your AKS cluster
2. **AKS cluster name** — the name of your AKS cluster
3. **Full image URI** — the full path to your pushed image (e.g., `myacr.azurecr.io/dotnet-jwt-mcont2-1929:latest`)
4. **AppSettings__Secret** — the JWT signing secret (entered without echo for security)

It will:
- Configure `kubectl` with your AKS cluster credentials via `az aks get-credentials`
- Create the `dotnet-jwt-mcont2-1929` namespace
- Create a Kubernetes Secret (`dotnet-jwt-mcont2-1929-secrets`) containing the JWT signing secret
- Replace placeholders in the deployment manifest and apply all Kubernetes manifests
- Wait for the rollout to complete
- Display the deployment status and application URL

### Using the batch script (Windows):

```cmd
scripts\deploy-image.bat
```

### Rollback on Failure

If the deployment fails or the new version has issues:

```bash
kubectl rollout undo deployment/dotnet-jwt-mcont2-1929 -n dotnet-jwt-mcont2-1929
```

---

## Kubernetes Manifests

### Namespace (`kubernetes/namespace.yaml`)
Creates an isolated namespace `dotnet-jwt-mcont2-1929` for the application and all its resources.

### Deployment (`kubernetes/deployment.yaml`)
- **Replicas**: 2 (for high availability)
- **Container port**: 8080
- **Image**: `{{IMAGE_URI}}` — replaced at deploy time by the deploy script
- **Environment variables**:
  - `ASPNETCORE_ENVIRONMENT=Production`
  - `ASPNETCORE_URLS=http://+:8080` (port controlled via environment variable, not hardcoded)
  - `TZ=UTC`
  - `AppSettings__Secret` — sourced from a Kubernetes Secret via `secretKeyRef`
  - `AppSettings__RefreshTokenTTL=2`
- **Resources**:
  - Requests: CPU 250m, Memory 512Mi
  - Limits: CPU 500m, Memory 1Gi
- **Liveness probe**: HTTP GET `/health` on port 8080 (initial delay 15s, period 20s)
- **Readiness probe**: HTTP GET `/health` on port 8080 (initial delay 10s, period 10s)

### Service (`kubernetes/service.yaml`)
- **Type**: ClusterIP
- **Port**: 80 → targetPort 8080
- Routes traffic from the AKS Service to the container port

### Ingress (`kubernetes/ingress.yaml`)
- **Ingress class**: `azure/application-gateway` (AGIC)
- **Host**: `dotnet-jwt-mcont2-1929.example.com`
- Routes all traffic (`/`) to the Service on port 80
- TLS is terminated at the Application Gateway layer

### Secret
The Kubernetes Secret `dotnet-jwt-mcont2-1929-secrets` stores:
- `appsettings-secret` — the JWT token signing secret

---

## Troubleshooting

### Pod Failures
- **CrashLoopBackOff**: Check pod logs with `kubectl logs <pod-name> -n dotnet-jwt-mcont2-1929`. Common causes include missing secrets or configuration errors.
- **Image pull errors**: Verify the image URI is correct and the ACR credentials are configured.
- **Readiness probe failures**: Ensure the application starts within the initial delay. Increase `initialDelaySeconds` if the application takes longer to start.

### Service Issues
- **Service not reachable**: Verify the Service selector matches the Deployment's pod labels (`app: dotnet-jwt-mcont2-1929`).
- **Port mismatch**: Ensure `targetPort` (8080) matches the container's listening port.

### Ingress Problems
- **Ingress not provisioned**: Ensure AGIC is installed and configured on your AKS cluster. Check the Application Gateway logs.
- **WebSocket issues**: Ensure your Application Gateway (WAF v2) has WebSocket support enabled.
- **503 Service Unavailable**: Check that the readiness probe is passing and pods are running.

### Common Checks
```bash
# Check pod status
kubectl get pods -n dotnet-jwt-mcont2-1929

# Check service
kubectl get svc -n dotnet-jwt-mcont2-1929

# Check ingress
kubectl get ingress -n dotnet-jwt-mcont2-1929

# Check deployment rollout status
kubectl rollout status deployment/dotnet-jwt-mcont2-1929 -n dotnet-jwt-mcont2-1929

# View pod logs
kubectl logs -f -n dotnet-jwt-mcont2-1929 <pod-name>
```

---

## Scaling and Management

### Horizontal Pod Autoscaler (HPA)
To enable automatic scaling based on CPU utilization:

```bash
kubectl autoscale deployment/dotnet-jwt-mcont2-1929 -n dotnet-jwt-mcont2-1929 --cpu-percent=70 --min=2 --max=10
```

You can also create a KEDA ScaledObject for HTTP-request-driven autoscaling by creating a `ScaledObject` manifest referencing the Service.

### Rolling Updates
The Deployment uses a rolling update strategy by default. To update the application:

1. Build and push a new image
2. Update the image in the deployment:

   ```bash
   kubectl set image deployment/dotnet-jwt-mcont2-1929 dotnet-jwt-mcont2-1929=<new-image-uri> -n dotnet-jwt-mcont2-1929
   ```

3. Monitor the rollout:

   ```bash
   kubectl rollout status deployment/dotnet-jwt-mcont2-1929 -n dotnet-jwt-mcont2-1929
   ```

### Rollbacks
If a rollout fails:

```bash
kubectl rollout undo deployment/dotnet-jwt-mcont2-1929 -n dotnet-jwt-mcont2-1929
```

To rollback to a specific revision:

```bash
kubectl rollout history deployment/dotnet-jwt-mcont2-1929 -n dotnet-jwt-mcont2-1929
kubectl rollout undo deployment/dotnet-jwt-mcont2-1929 --to-revision=<revision> -n dotnet-jwt-mcont2-1929
```

---

## .NET Notes

### Runtime Configuration
- **Target framework**: .NET 6.0
- **Base image**: `mcr.microsoft.com/dotnet/runtime:6.0`
- **Deployment type**: Self-contained publish (`--self-contained true -r linux-x64`)
  - The runtime image does not include the ASP.NET Core shared framework, so the application is published self-contained to ensure all dependencies are available.
- **Environment**: `ASPNETCORE_ENVIRONMENT=Production`
- **Listening port**: Controlled via `ASPNETCORE_URLS=http://+:8080` (set via environment variable, not hardcoded in code)
- **Time zone**: `TZ=UTC`
- **Globalization**: `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false` for full globalization support

### Garbage Collector Tuning
For containerized workloads, the .NET 6 runtime automatically uses the Server Garbage Collector in containers. The memory limit (1Gi) is respected by the GC for heap sizing. No additional GC configuration is needed for this application's workload.

### Monitoring
- The application exposes a health check endpoint at `/health` for liveness and readiness probes.
- Application logging is configured via `appsettings.json` with `LogLevel` settings. For production, consider integrating with Azure Application Insights or a structured logging provider like Serilog.

### Security
- **Non-root user**: The container runs as a non-root user (`appuser`) for security.
- **HTTPS redirection**: TLS is terminated at the Application Gateway Ingress layer. The application itself listens on HTTP (port 8080) since the ingress handles TLS termination. For direct HTTPS exposure, configure `ASPNETCORE_HTTPS_PORT` and mount certificates.
- **Security headers**: Consider adding security headers (e.g., `X-Content-Type-Options`, `X-Frame-Options`, `Strict-Transport-Security`) via middleware or the ingress layer.
- **Authentication and Authorization**: The API uses JWT bearer tokens for authentication. The `[Authorize]` attribute protects endpoints by default, with `[AllowAnonymous]` on specific endpoints (authenticate, refresh-token).
- **CORS**: The application has a permissive CORS policy (`SetIsOriginAllowed(origin => true)`) configured for development. For production, restrict to specific origins.
- **Data protection**: The in-memory database is used for development/testing. For production, replace with a persistent data store and ensure connection strings are provided via environment variables or Kubernetes Secrets.
- **JWT secret**: The `AppSettings__Secret` is provided via Kubernetes Secret, never hardcoded in the image or configuration files.
