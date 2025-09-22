#!/bin/bash

# Install Docker on Ubuntu

# Update and install prerequisites
echo "Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
echo "Adding Docker GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository
echo "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index
echo "Updating package index..."
sudo apt-get update

# Install Docker
echo "Installing Docker..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
echo "Adding $USER to docker group..."
sudo usermod -aG docker $USER

# Test Docker
echo "Testing Docker installation..."
sudo docker run hello-world

# Show versions
echo ""
echo "Docker installed:"
docker --version
docker compose version

echo ""
echo "NOTE: Log out and back in for docker group membership to take effect."
echo "After that, you can run docker without sudo."