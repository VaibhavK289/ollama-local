#!/usr/bin/env bash
# =============================================================================
# Allma AI Studio - Database Backup Script
# Automated backup for SQLite and ChromaDB vector store
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "Starting backup at $TIMESTAMP..."

# Backup SQLite database
if docker volume inspect allma-database &> /dev/null; then
    echo "Backing up database..."
    docker run --rm \
        -v allma-database:/data \
        -v "$BACKUP_DIR:/backup" \
        alpine \
        tar czf "/backup/database_${TIMESTAMP}.tar.gz" -C /data .
    echo "Database backup complete: database_${TIMESTAMP}.tar.gz"
fi

# Backup vector store
if docker volume inspect allma-vectorstore &> /dev/null; then
    echo "Backing up vector store..."
    docker run --rm \
        -v allma-vectorstore:/data \
        -v "$BACKUP_DIR:/backup" \
        alpine \
        tar czf "/backup/vectorstore_${TIMESTAMP}.tar.gz" -C /data .
    echo "Vector store backup complete: vectorstore_${TIMESTAMP}.tar.gz"
fi

# Cleanup old backups (keep last 7 days)
echo "Cleaning up old backups..."
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed successfully!"
echo "Backup location: $BACKUP_DIR"
ls -lah "$BACKUP_DIR"
