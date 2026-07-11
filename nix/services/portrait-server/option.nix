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
            }
            // lib.neo.mkContainerDefinitions {
              portrait-server = "madebydamo/portrait-server:latest";
            }
            // lib.neo.mkServiceMeta {
              icon = "https://static.thenounproject.com/png/cv-icon-4553192-512.png";
              description = ''
                This is my portrait and also kinda my CV.
              '';
              projectUrl = "https://damianmoser.ch/";
              githubUrl = "https://github.com/madebydamo/portrait";
            };
        };
        default = {};
        description = "Portrait server configuration";
      };
    };
}
