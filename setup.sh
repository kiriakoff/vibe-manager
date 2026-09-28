#!/bin/bash
# Setup script for Linux hosts
set -e

echo "Setting up Vibe Manager data directories..."
mkdir -p /data/vibemanager/auth
mkdir -p /data/vibemanager/previews
mkdir -p /data/vibemanager/compose
mkdir -p /data/filebrowser/files

echo ""
echo "Data directories created!"
echo ""

echo "Building Docker image..."
docker compose build

echo ""
echo "Creating default admin user..."
docker compose run --rm vibemanager /app/create-user admin admin123

echo ""
echo "Starting Vibe Manager..."
docker compose up -d

echo ""
echo "Done! Default credentials:"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Please change the password immediately after first login:"
echo "  docker compose run --rm vibemanager /app/create-user <user> <new-password>"
