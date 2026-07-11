# Portrait-server service implementation.
{...}: {
  flake.modules.nixos.portrait-server = {
    config,
    lib,
    ...
  }:
    with lib; let
      cfg = config.neo.services.portrait-server;
      portraitEnv = lib.filterAttrs (_: v: v != null && v != "") {
        TELEGRAM_BOT_TOKEN = cfg.telegramBotToken;
        TELEGRAM_CHAT_ID = cfg.telegramChatId;
      };
    in {
      config = mkIf cfg.enabled {
        virtualisation.oci-containers.containers.portrait-server = {
          environment =
            portraitEnv
            // {
              ROCKET_PORT = "7999";
              ROCKET_ADDRESS = "0.0.0.0";
            };
          image = cfg.containers.portrait-server;
          autoStart = true;
          extraOptions = [
            "--cap-add=SYS_ADMIN"
            "--security-opt=seccomp=unconfined"
          ];
        };
      };
    };
}
