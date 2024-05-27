#!/usr/bin/env bash

# Configuration du dossier pour GitLab
mkdir -p /apps/docker/gitlab/config
mkdir -p /apps/docker/gitlab/logs
mkdir -p /apps/docker/gitlab/data

# Création du fichier docker-compose.yml
cat <<EOF > /apps/docker/gitlab/docker-compose.yml
version: '3.6'
services:
  gitlab:
    image: 'gitlab/gitlab-ce:latest'
    restart: always
    hostname: 'gitlab.example.com'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://gitlab.example.com'
        gitlab_rails['gitlab_shell_ssh_port'] = 2222
    ports:
      - '80:80'
      - '443:443'
      - '2222:22'
    volumes:
      - '/apps/docker/gitlab/config:/etc/gitlab'
      - '/app/docker/gitlab/logs:/var/log/gitlab'
      - '/apps/docker/gitlab/data:/var/opt/gitlab'
EOF

# Démarrage de GitLab via docker-compose
cd /apps/docker/gitlab
docker-compose up -d

echo "GitLab est maintenant configuré et en cours d'exécution."