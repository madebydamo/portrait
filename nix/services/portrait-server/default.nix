# Portrait-server service implementation.
{withSystem, ...}: {
  flake.modules.nixos.portrait-server = {
    config,
    lib,
    pkgs,
    ...
  }:
    with lib; let
      cfg = config.neo.services.portrait-server;
      portraitEnv = lib.filterAttrs (_: v: v != null && v != "") {
        TELEGRAM_BOT_TOKEN = cfg.telegramBotToken;
        TELEGRAM_CHAT_ID = cfg.telegramChatId;
      };
      image = withSystem pkgs.stdenv.hostPlatform.system ({config, ...}: config.packages.portrait-server-image);
      docker = "${config.virtualisation.docker.package}/bin/docker";
    in {
      config = mkIf cfg.enabled {
        # Loads the Nix-built image into Docker ahead of the container unit.
        # The tag is the image hash, so a new build is loaded once and an
        # unchanged one is skipped. A changed image changes this unit, so
        # switch reruns it before restarting docker-portrait-server.
        systemd.services.portrait-server-image = {
          description = "Load the portrait-server image into Docker";
          after = ["docker.service" "docker.socket"];
          requires = ["docker.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            if ! ${docker} image inspect ${image.imageRefUnsafe} >/dev/null 2>&1; then
              ${image.copyToDockerDaemon}/bin/copy-to-docker-daemon
            fi
            # Drop superseded builds. One still used by the running container
            # is refused here and removed on the next run.
            ${docker} image ls ${image.imageName} --format '{{.Repository}}:{{.Tag}}' \
              | grep -vxF ${image.imageRefUnsafe} \
              | xargs -r ${docker} rmi 2>/dev/null || true
          '';
        };

        systemd.services.docker-portrait-server = {
          requires = ["portrait-server-image.service"];
          after = ["portrait-server-image.service"];
        };

        virtualisation.oci-containers.containers.portrait-server = {
          environment =
            portraitEnv
            // {
              ROCKET_PORT = "7999";
              ROCKET_ADDRESS = "0.0.0.0";
              PORTRAIT_SANDBOX_FW = "1";
            };
          image = cfg.containers.portrait-server;
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
