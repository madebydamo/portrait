# Portrait-server service implementation.
# One container on its own network (app-<name>); with the VPN on (the default)
# it runs in gluetun's network namespace and gluetun answers for its name there.
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
      image = withSystem pkgs.stdenv.hostPlatform.system ({config, ...}: config.packages.portrait-server-image);
      docker = "${config.virtualisation.docker.package}/bin/docker";
      # Every copy loads the image under its own name, so one copy's cleanup
      # never removes the image of another.
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
            # Loaded straight under this copy's name: another copy never sees
            # (or removes) this tag.
            if ! ${docker} image inspect ${localRef} >/dev/null 2>&1; then
              ${image.copyTo}/bin/copy-to docker-daemon:${localRef}
            fi
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

        # The bot token reaches the container through a rendered env file,
        # never the Nix store.
        neo.core.secrets.containerEnv.${name} = optionalAttrs (lib.neo.isSet cfg.telegramBotToken) {
          TELEGRAM_BOT_TOKEN = cfg.telegramBotToken;
        };

        virtualisation.oci-containers.containers.${name} = {
          image = cfg.containers.${name};
          networks = [(lib.neo.docker.serviceNetwork name)];
          environment =
            {
              ROCKET_PORT = toString cfg.port;
              ROCKET_ADDRESS = "0.0.0.0";
              # Fail closed: no sandbox without its egress firewall.
              PORTRAIT_SANDBOX_FW = "1";
              TZ = config.neo.core.timeZone;
            }
            // optionalAttrs (lib.neo.isSet cfg.telegramChatId) {
              TELEGRAM_CHAT_ID = cfg.telegramChatId;
            };
          # SYS_ADMIN + seccomp=unconfined: bwrap's namespaces. NET_ADMIN: the
          # sandbox firewall (iptables + nftables) in the shared VPN namespace.
          # The sandboxed shell itself drops every capability (setpriv).
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
