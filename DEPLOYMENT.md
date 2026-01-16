# Allma AI Studio - Deployment Guide

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Options](#deployment-options)
- [Configuration](#configuration)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)

---

## Overview

Allma AI Studio is a full-stack RAG (Retrieval-Augmented Generation) application consisting of:

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Backend** | FastAPI + Python 3.11 | API orchestration, RAG pipeline |
| **Frontend** | React 18 + Vite + Nginx | Web interface |
| **LLM** | Ollama | Local LLM inference |
| **Vector Store** | ChromaDB | Document embeddings storage |
| **Database** | SQLite + SQLAlchemy | Conversation persistence |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                    │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │      NGINX / Ingress      │
                    │   (TLS, Rate Limiting)    │
                    └─────────────┬─────────────┘
                                  │
          ┌───────────────────────┴───────────────────────┐
          │                                               │
┌─────────▼─────────┐                       ┌─────────────▼─────────────┐
│     Frontend      │                       │         Backend           │
│   (React + Nginx) │                       │        (FastAPI)          │
│     Port: 80      │                       │       Port: 8000          │
└───────────────────┘                       └─────────────┬─────────────┘
                                                          │
                          ┌───────────────────────────────┴───────────────┐
                          │                                               │
                ┌─────────▼─────────┐                       ┌─────────────▼─────────┐
                │      Ollama       │                       │      ChromaDB         │
                │  (LLM Inference)  │                       │   (Vector Store)      │
                │   Port: 11434     │                       │    (Embedded)         │
                └───────────────────┘                       └───────────────────────┘
```

---

## Prerequisites

### System Requirements

| Resource | Development | Production |
|----------|-------------|------------|
| **CPU** | 4 cores | 8+ cores |
| **RAM** | 16 GB | 32+ GB |
| **GPU** | NVIDIA 8GB+ VRAM | NVIDIA 16GB+ VRAM |
| **Storage** | 50 GB | 100+ GB |
| **OS** | Windows/macOS/Linux | Linux (Ubuntu 22.04+) |

### Software Requirements

- **Docker** 24.0+ with Compose V2
- **NVIDIA Container Toolkit** (for GPU support)
- **Git** 2.40+
- **kubectl** 1.28+ (for Kubernetes)
- **Helm** 3.12+ (optional)

### GPU Setup (NVIDIA)

```bash
# Install NVIDIA Container Toolkit (Ubuntu/Debian)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

---

## Quick Start

### Option 1: PowerShell (Windows)

```powershell
# Clone repository
git clone https://github.com/allma-studio/allma-studio.git
cd allma-studio

# Start development environment
.\scripts\deploy.ps1 development up -d

# Check status
.\scripts\deploy.ps1 status
```

### Option 2: Bash (Linux/macOS)

```bash
# Clone repository
git clone https://github.com/allma-studio/allma-studio.git
cd allma-studio

# Make scripts executable
chmod +x scripts/*.sh

# Start development environment
./scripts/deploy.sh development up -d

# Check status
./scripts/deploy.sh status
```

### Option 3: Direct Docker Compose

```bash
# Development
cp .env.example .env
docker compose -f docker-compose.yml up -d

# Production
docker compose -f docker-compose.prod.yml up -d
```

---

## Deployment Options

### 1. Docker Compose (Development)

Best for: Local development, testing, small teams

```bash
# Start with hot-reload
docker compose up

# Start detached
docker compose up -d

# View logs
docker compose logs -f backend

# Stop
docker compose down
```

**Services:**
- Frontend: http://localhost:5173 (Vite dev server)
- Backend: http://localhost:8000
- API Docs: http://localhost:8000/docs
- Ollama: http://localhost:11434

### 2. Docker Compose (Production)

Best for: Single-server production, small-medium deployments

```bash
# Build and deploy
docker compose -f docker-compose.prod.yml up -d --build

# With SSL certificates
# 1. Place certificates in ./certs/
# 2. Update nginx configuration
docker compose -f docker-compose.prod.yml up -d
```

**Services:**
- Frontend: http://localhost:80 (Nginx)
- Backend: Internal (proxied via Nginx)
- Ollama: Internal only

### 3. Kubernetes (Kustomize)

Best for: Cloud-native deployments, high availability

```bash
# Apply base configuration
kubectl apply -k k8s/base/

# Apply production overlay
kubectl apply -k k8s/overlays/production/

# Check deployment
kubectl get pods -n allma-studio
kubectl get services -n allma-studio
```

### 4. Kubernetes (Helm)

Best for: Complex deployments, GitOps workflows

```bash
# Add Ollama Helm repo
helm repo add ollama https://otwld.github.io/ollama-helm/

# Install Allma Studio
helm install allma-studio ./helm/allma-studio \
  --namespace allma-studio \
  --create-namespace \
  --values ./helm/allma-studio/values.yaml

# Upgrade
helm upgrade allma-studio ./helm/allma-studio \
  --namespace allma-studio \
  --values ./helm/allma-studio/values.yaml
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_MODEL` | `deepseek-r1:latest` | LLM model for chat |
| `OLLAMA_EMBEDDING_MODEL` | `nomic-embed-text:latest` | Embedding model for RAG |
| `OLLAMA_HOST` | `http://ollama:11434` | Ollama server URL |
| `LOG_LEVEL` | `INFO` | Logging level |
| `CORS_ORIGINS` | `*` | Allowed CORS origins |
| `VECTOR_STORE_PATH` | `/app/data/vectorstore` | ChromaDB storage path |
| `DATABASE_URL` | `sqlite+aiosqlite:///./data/allma.db` | Database connection |

### Available Ollama Models

```bash
# Pull models manually
docker compose exec ollama ollama pull deepseek-r1:latest
docker compose exec ollama ollama pull nomic-embed-text:latest
docker compose exec ollama ollama pull gemma2:9b
docker compose exec ollama ollama pull qwen2.5-coder:7b
```

### SSL/TLS Configuration

For production with HTTPS:

1. **Using Let's Encrypt with Certbot:**
```bash
sudo certbot certonly --standalone -d your-domain.com
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem ./certs/
cp /etc/letsencrypt/live/your-domain.com/privkey.pem ./certs/
```

2. **Update nginx configuration** in `nginx/custom.conf`:
```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    
    # ... rest of config
}
```

---

## Monitoring & Maintenance

### Health Checks

```bash
# Backend health
curl http://localhost:8000/health/

# Frontend health
curl http://localhost/health

# Ollama health
curl http://localhost:11434/api/version
```

### Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f backend
docker compose logs -f ollama

# Kubernetes
kubectl logs -f deployment/backend -n allma-studio
```

### Backups

```bash
# Run backup script
./scripts/backup.sh

# Manual backup
docker run --rm \
  -v allma-vectorstore:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/vectorstore_$(date +%Y%m%d).tar.gz -C /data .
```

### Updates

```bash
# Pull latest images
docker compose pull

# Rebuild and restart
docker compose up -d --build

# For Kubernetes
kubectl rollout restart deployment/backend -n allma-studio
kubectl rollout restart deployment/frontend -n allma-studio
```

---

## Troubleshooting

### Common Issues

#### 1. Ollama GPU Not Detected

```bash
# Verify NVIDIA runtime
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi

# Check container GPU access
docker compose exec ollama nvidia-smi
```

#### 2. Backend Can't Connect to Ollama

```bash
# Check Ollama is running
docker compose exec backend curl http://ollama:11434/api/version

# Check network
docker network ls
docker network inspect allma-network
```

#### 3. Frontend API Errors

```bash
# Check backend logs
docker compose logs backend

# Verify CORS settings
curl -H "Origin: http://localhost:5173" \
     -H "Access-Control-Request-Method: POST" \
     -X OPTIONS http://localhost:8000/chat/
```

#### 4. ChromaDB Errors

```bash
# Check volume permissions
docker compose exec backend ls -la /app/data/vectorstore

# Reset vector store
docker volume rm allma-vectorstore
docker compose up -d
```

#### 5. Out of Memory

```bash
# Check resource usage
docker stats

# Limit Ollama memory
# In docker-compose.yml, add under ollama service:
deploy:
  resources:
    limits:
      memory: 12G
```

### Debug Mode

```bash
# Start with debug logging
LOG_LEVEL=DEBUG docker compose up

# Interactive shell into container
docker compose exec backend /bin/bash
docker compose exec ollama /bin/bash
```

---

## Security Checklist

- [ ] Change default ports in production
- [ ] Enable HTTPS/TLS
- [ ] Configure proper CORS origins
- [ ] Set up firewall rules
- [ ] Enable rate limiting
- [ ] Regular security updates
- [ ] Backup encryption
- [ ] Access logging enabled
- [ ] Non-root container users
- [ ] Network policies (Kubernetes)

---

## Support

- **Documentation:** [docs.allma.studio](https://docs.allma.studio)
- **Issues:** [GitHub Issues](https://github.com/allma-studio/allma-studio/issues)
- **Discussions:** [GitHub Discussions](https://github.com/allma-studio/allma-studio/discussions)

---

*Last updated: January 2026*
