#!/usr/bin/env bash
# =============================================================================
# Allma AI Studio - Deployment Script
# Automated deployment for Docker Compose environments
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
ENVIRONMENT="${1:-development}"
ACTION="${2:-up}"

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    ALLMA AI STUDIO                            ║"
    echo "║              Deployment Automation Script                     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    log_success "All prerequisites met."
}

setup_environment() {
    log_info "Setting up environment for: $ENVIRONMENT"
    
    cd "$PROJECT_ROOT"
    
    # Create .env file if it doesn't exist
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            log_info "Created .env from .env.example"
        else
            log_warning "No .env.example found. Using defaults."
        fi
    fi
    
    # Create required directories
    mkdir -p certs nginx
    
    # Create empty custom nginx config if not exists
    if [[ ! -f nginx/custom.conf ]]; then
        echo "# Custom nginx configuration" > nginx/custom.conf
    fi
}

pull_ollama_models() {
    log_info "Pulling Ollama models..."
    
    local OLLAMA_MODEL="${OLLAMA_MODEL:-deepseek-r1:latest}"
    local OLLAMA_EMBEDDING_MODEL="${OLLAMA_EMBEDDING_MODEL:-nomic-embed-text:latest}"
    
    # Wait for Ollama to be ready
    local max_attempts=30
    local attempt=0
    
    while ! docker compose exec -T ollama curl -s http://localhost:11434/api/version > /dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            log_warning "Ollama not ready after ${max_attempts} attempts. Models will need to be pulled manually."
            return 0
        fi
        log_info "Waiting for Ollama to be ready... (${attempt}/${max_attempts})"
        sleep 5
    done
    
    log_info "Pulling LLM model: $OLLAMA_MODEL"
    docker compose exec -T ollama ollama pull "$OLLAMA_MODEL" || true
    
    log_info "Pulling embedding model: $OLLAMA_EMBEDDING_MODEL"
    docker compose exec -T ollama ollama pull "$OLLAMA_EMBEDDING_MODEL" || true
    
    log_success "Ollama models ready."
}

deploy_development() {
    log_info "Deploying DEVELOPMENT environment..."
    
    docker compose -f docker-compose.yml "$ACTION" "${@:3}"
    
    if [[ "$ACTION" == "up" ]]; then
        log_info "Waiting for services to start..."
        sleep 10
        pull_ollama_models
    fi
}

deploy_production() {
    log_info "Deploying PRODUCTION environment..."
    
    # Build images first
    log_info "Building production images..."
    docker compose -f docker-compose.prod.yml build --no-cache
    
    # Deploy
    docker compose -f docker-compose.prod.yml "$ACTION" "${@:3}"
    
    if [[ "$ACTION" == "up" ]]; then
        log_info "Waiting for services to start..."
        sleep 15
        pull_ollama_models
    fi
}

show_status() {
    log_info "Service Status:"
    echo ""
    
    if [[ "$ENVIRONMENT" == "production" ]]; then
        docker compose -f docker-compose.prod.yml ps
    else
        docker compose -f docker-compose.yml ps
    fi
    
    echo ""
    log_info "Service URLs:"
    echo "  - Frontend: http://localhost:80 (prod) or http://localhost:5173 (dev)"
    echo "  - Backend API: http://localhost:8000"
    echo "  - API Docs: http://localhost:8000/docs"
    echo "  - Ollama: http://localhost:11434"
}

show_logs() {
    local service="${3:-}"
    
    if [[ "$ENVIRONMENT" == "production" ]]; then
        docker compose -f docker-compose.prod.yml logs -f $service
    else
        docker compose -f docker-compose.yml logs -f $service
    fi
}

cleanup() {
    log_info "Cleaning up..."
    
    docker compose -f docker-compose.yml down -v --remove-orphans 2>/dev/null || true
    docker compose -f docker-compose.prod.yml down -v --remove-orphans 2>/dev/null || true
    
    docker system prune -f
    
    log_success "Cleanup complete."
}

show_help() {
    echo "Usage: $0 [environment] [action] [options]"
    echo ""
    echo "Environments:"
    echo "  development    Development environment with hot-reload (default)"
    echo "  production     Production environment with Nginx"
    echo ""
    echo "Actions:"
    echo "  up             Start services (default)"
    echo "  down           Stop services"
    echo "  restart        Restart services"
    echo "  build          Build images"
    echo "  logs           Show logs"
    echo "  status         Show service status"
    echo "  cleanup        Remove all containers and volumes"
    echo ""
    echo "Examples:"
    echo "  $0                           # Start development"
    echo "  $0 development up -d         # Start development detached"
    echo "  $0 production up -d          # Start production"
    echo "  $0 development logs backend  # Show backend logs"
    echo "  $0 cleanup                   # Clean everything"
}

# =============================================================================
# Main
# =============================================================================

print_banner

case "$ACTION" in
    help|--help|-h)
        show_help
        exit 0
        ;;
    status)
        show_status
        exit 0
        ;;
    logs)
        show_logs "$@"
        exit 0
        ;;
    cleanup)
        cleanup
        exit 0
        ;;
esac

check_prerequisites
setup_environment

case "$ENVIRONMENT" in
    development|dev)
        deploy_development "$@"
        ;;
    production|prod)
        deploy_production "$@"
        ;;
    *)
        log_error "Unknown environment: $ENVIRONMENT"
        show_help
        exit 1
        ;;
esac

if [[ "$ACTION" == "up" ]]; then
    show_status
    log_success "Deployment complete!"
fi
