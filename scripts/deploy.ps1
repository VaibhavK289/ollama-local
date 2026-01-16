# =============================================================================
# Allma AI Studio - Deployment Script (PowerShell)
# Windows deployment automation
# =============================================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("development", "production", "dev", "prod")]
    [string]$Environment = "development",
    
    [Parameter(Position=1)]
    [ValidateSet("up", "down", "restart", "build", "logs", "status", "cleanup")]
    [string]$Action = "up",
    
    [Parameter(Position=2, ValueFromRemainingArguments)]
    [string[]]$ExtraArgs
)

# Colors
$Colors = @{
    Info = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
}

function Write-Log {
    param([string]$Message, [string]$Level = "Info")
    $prefix = "[$Level]"
    Write-Host $prefix -ForegroundColor $Colors[$Level] -NoNewline
    Write-Host " $Message"
}

function Show-Banner {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    ALLMA AI STUDIO                            ║" -ForegroundColor Cyan
    Write-Host "║              Deployment Automation Script                     ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "Info"
    
    # Check Docker
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Log "Docker is not installed. Please install Docker Desktop." "Error"
        exit 1
    }
    
    # Check Docker daemon
    try {
        docker info 2>&1 | Out-Null
    } catch {
        Write-Log "Docker daemon is not running. Please start Docker Desktop." "Error"
        exit 1
    }
    
    Write-Log "All prerequisites met." "Success"
}

function Initialize-Environment {
    Write-Log "Setting up environment for: $Environment" "Info"
    
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Set-Location $projectRoot
    
    # Create .env if not exists
    if (-not (Test-Path ".env")) {
        if (Test-Path ".env.example") {
            Copy-Item ".env.example" ".env"
            Write-Log "Created .env from .env.example" "Info"
        }
    }
    
    # Create directories
    New-Item -ItemType Directory -Force -Path "certs" | Out-Null
    New-Item -ItemType Directory -Force -Path "nginx" | Out-Null
    
    # Create empty custom nginx config
    if (-not (Test-Path "nginx\custom.conf")) {
        "# Custom nginx configuration" | Out-File -FilePath "nginx\custom.conf" -Encoding UTF8
    }
}

function Start-OllamaModels {
    Write-Log "Pulling Ollama models..." "Info"
    
    $ollamaModel = $env:OLLAMA_MODEL
    if (-not $ollamaModel) { $ollamaModel = "deepseek-r1:latest" }
    
    $embeddingModel = $env:OLLAMA_EMBEDDING_MODEL
    if (-not $embeddingModel) { $embeddingModel = "nomic-embed-text:latest" }
    
    # Wait for Ollama
    $maxAttempts = 30
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        try {
            $result = docker compose exec -T ollama curl -s http://localhost:11434/api/version 2>&1
            if ($LASTEXITCODE -eq 0) { break }
        } catch {}
        
        $attempt++
        Write-Log "Waiting for Ollama... ($attempt/$maxAttempts)" "Info"
        Start-Sleep -Seconds 5
    }
    
    if ($attempt -ge $maxAttempts) {
        Write-Log "Ollama not ready. Models need manual pull." "Warning"
        return
    }
    
    Write-Log "Pulling LLM model: $ollamaModel" "Info"
    docker compose exec -T ollama ollama pull $ollamaModel
    
    Write-Log "Pulling embedding model: $embeddingModel" "Info"
    docker compose exec -T ollama ollama pull $embeddingModel
    
    Write-Log "Ollama models ready." "Success"
}

function Start-Development {
    Write-Log "Deploying DEVELOPMENT environment..." "Info"
    
    $args = @($Action) + $ExtraArgs
    docker compose -f docker-compose.yml @args
    
    if ($Action -eq "up") {
        Write-Log "Waiting for services..." "Info"
        Start-Sleep -Seconds 10
        Start-OllamaModels
    }
}

function Start-Production {
    Write-Log "Deploying PRODUCTION environment..." "Info"
    
    Write-Log "Building production images..." "Info"
    docker compose -f docker-compose.prod.yml build --no-cache
    
    $args = @($Action) + $ExtraArgs
    docker compose -f docker-compose.prod.yml @args
    
    if ($Action -eq "up") {
        Write-Log "Waiting for services..." "Info"
        Start-Sleep -Seconds 15
        Start-OllamaModels
    }
}

function Show-Status {
    Write-Log "Service Status:" "Info"
    Write-Host ""
    
    if ($Environment -in @("production", "prod")) {
        docker compose -f docker-compose.prod.yml ps
    } else {
        docker compose -f docker-compose.yml ps
    }
    
    Write-Host ""
    Write-Log "Service URLs:" "Info"
    Write-Host "  - Frontend: http://localhost:80 (prod) or http://localhost:5173 (dev)"
    Write-Host "  - Backend API: http://localhost:8000"
    Write-Host "  - API Docs: http://localhost:8000/docs"
    Write-Host "  - Ollama: http://localhost:11434"
}

function Show-Logs {
    $service = if ($ExtraArgs.Count -gt 0) { $ExtraArgs[0] } else { "" }
    
    if ($Environment -in @("production", "prod")) {
        docker compose -f docker-compose.prod.yml logs -f $service
    } else {
        docker compose -f docker-compose.yml logs -f $service
    }
}

function Start-Cleanup {
    Write-Log "Cleaning up..." "Info"
    
    docker compose -f docker-compose.yml down -v --remove-orphans 2>$null
    docker compose -f docker-compose.prod.yml down -v --remove-orphans 2>$null
    docker system prune -f
    
    Write-Log "Cleanup complete." "Success"
}

# =============================================================================
# Main
# =============================================================================

Show-Banner

switch ($Action) {
    "status" {
        Show-Status
        exit 0
    }
    "logs" {
        Show-Logs
        exit 0
    }
    "cleanup" {
        Start-Cleanup
        exit 0
    }
}

Test-Prerequisites
Initialize-Environment

switch ($Environment) {
    { $_ -in @("development", "dev") } {
        Start-Development
    }
    { $_ -in @("production", "prod") } {
        Start-Production
    }
}

if ($Action -eq "up") {
    Show-Status
    Write-Log "Deployment complete!" "Success"
}
