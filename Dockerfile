FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build
WORKDIR /src

# Copy project file and restore as distinct layers
COPY WebApi.csproj ./
RUN dotnet restore

# Copy everything else and build
COPY . ./
RUN dotnet publish -c Release -r linux-x64 --self-contained true -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/runtime:6.0
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_ENVIRONMENT=Production \
    ASPNETCORE_URLS=http://+:8080 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    TZ=UTC

# Copy published self-contained output
COPY --from=build /app/publish ./

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser
USER appuser

# Enable graceful shutdown
ENTRYPOINT ["./WebApi"]
