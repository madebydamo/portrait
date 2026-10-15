# Local dev: build the image with Nix, load it into Docker, run it like the
# homeserver does. ./www is bind-mounted so page edits need no rebuild.

name := "portrait"
port := "8000"

# Run in the foreground (Ctrl-C stops and removes the container)
default: run

# Build the image and load it into Docker unless that tag is already there
load:
    #!/usr/bin/env bash
    set -euo pipefail
    image=$(nix eval --raw .#portrait-server-image.imageRefUnsafe)
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        nix run .#portrait-server-image.copyToDockerDaemon
    fi

# Run in the foreground
run: load (_docker "--rm")

# Run in the background
up: load (_docker "-d --restart unless-stopped")

# Stop and remove the background container
down:
    docker rm -f {{ name }}

logs:
    docker logs -f {{ name }}

# Remove every loaded portrait-server image
clean: down
    docker image ls portrait-server --format '{{{{.Repository}}:{{{{.Tag}}' | xargs -r docker rmi

_docker flags:
    #!/usr/bin/env bash
    set -euo pipefail
    image=$(nix eval --raw .#portrait-server-image.imageRefUnsafe)
    env_file=()
    [ -f .env ] && env_file=(--env-file .env)
    docker rm -f {{ name }} >/dev/null 2>&1 || true
    exec docker run {{ flags }} --name {{ name }} --hostname {{ name }} \
        "${env_file[@]}" \
        -e ROCKET_PORT={{ port }} -e ROCKET_ADDRESS=0.0.0.0 \
        -p {{ port }}:{{ port }} \
        -v "$PWD/www:/home/damo/www:ro" \
        --cap-add SYS_ADMIN --security-opt seccomp=unconfined \
        "$image"
