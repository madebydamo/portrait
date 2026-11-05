# Portrait-server service implementation.
{withSystem, ...}: {
  neoPlugin.modules.portrait-server = {
    config,
    lib,
    pkgs,
    plugin,
    ...
  }:
    with lib; let
      # "portrait-server", or "<prefix>-portrait-server" for a prefixed copy.
      name = plugin.name "portrait-server";
      cfg = config.neo.services.${name};
      portraitEnv = lib.filterAttrs (_: v: v != null && v != "") {
        TELEGRAM_BOT_TOKEN = cfg.telegramBotToken;
        TELEGRAM_CHAT_ID = cfg.telegramChatId;
      };
      image = withSystem pkgs.stdenv.hostPlatform.system ({config, ...}: config.packages.portrait-server-image);
      docker = "${config.virtualisation.docker.package}/bin/docker";
      # Every copy tags the image under its own name, so one copy's cleanup never
      # removes the image another copy is about to start.
      localRef = "${name}:${image.imageTag}";
    in {
      config = mkIf cfg.enabled {
        # Loads the Nix-built image into Docker ahead of the container unit.
        # The tag is the image hash, so a new build is loaded once and an
        # unchanged one is skipped. A changed image changes this unit, so
        # switch reruns it before restarting docker-${name}.
        systemd.services."${name}-image" = {
          description = "Load the ${name} image into Docker";
          after = ["docker.service" "docker.socket"];
          requires = ["docker.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            if ! ${docker} image inspect ${localRef} >/dev/null 2>&1; then
              if ! ${docker} image inspect ${image.imageRefUnsafe} >/dev/null 2>&1; then
                ${image.copyToDockerDaemon}/bin/copy-to-docker-daemon
              fi
              ${docker} tag ${image.imageRefUnsafe} ${localRef}
            fi
            ${optionalString (localRef != image.imageRefUnsafe) ''
              # Only the tag; the image stays under ${localRef}.
              ${docker} rmi ${image.imageRefUnsafe} >/dev/null 2>&1 || true
            ''}
            # Drop this copy's superseded builds. One still used by the running
            # container is refused here and removed on the next run.
            ${docker} image ls ${name} --format '{{.Repository}}:{{.Tag}}' \
              | grep -vxF ${localRef} \
              | xargs -r ${docker} rmi 2>/dev/null || true
          '';
        };

        systemd.services."docker-${name}" = {
          requires = ["${name}-image.service"];
          after = ["${name}-image.service"];
        };

        virtualisation.oci-containers.containers.${name} = {
          environment =
            portraitEnv
            // {
              ROCKET_PORT = "7999";
              ROCKET_ADDRESS = "0.0.0.0";
              PORTRAIT_SANDBOX_FW = "1";
            };
          image = cfg.containers.${name};
          autoStart = true;
          capabilities = {
            SYS_ADMIN = true;
            NET_ADMIN = true;
          };
          extraOptions = [
            "--security-opt=seccomp=unconfined"
          ];
        };
      };
    };
}
