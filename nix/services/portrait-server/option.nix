# Portrait-server service options.
{...}: {
  flake.modules.nixos.portrait-server-option = {
    config,
    lib,
    ...
  }:
    with lib; {
      options.neo.services.portrait-server = mkOption {
        type = types.submodule {
          options =
            {
              enabled = mkEnableOption "portrait-server service";
              telegramBotToken = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Telegram bot token";
              };
              telegramChatId = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Telegram chat ID";
              };
            }
            // neo.mkVpnOptions {
              containers = ["portrait-server"];
              networks = ["internal"];
              ports = [7779];
              enabled = true;
            }
            // neo.mkReverseProxyOptions {
              subdomain = "portrait";
              auth.enabled = false;
            };
        };
        default = {};
        description = "Portrait server configuration";
      };
    };
}
