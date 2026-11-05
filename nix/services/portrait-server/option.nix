# Portrait-server service options.
{withSystem, ...}: {
  neoPlugin.modules.portrait-server-option = {
    config,
    lib,
    pkgs,
    plugin,
    ...
  }:
    with lib; let
      name = plugin.name "portrait-server";
      image = withSystem pkgs.stdenv.hostPlatform.system ({config, ...}: config.packages.portrait-server-image);
    in {
      options.neo.services.${name} = mkOption {
        type = types.submodule {
          options =
            {
              enabled = mkEnableOption "portrait-server service${plugin.label}";
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
              containers = [name];
              networks = ["internal"];
              ports = [7999];
              enabled = true;
            }
            // neo.mkReverseProxyOptions {
              subdomain = plugin.name "portrait";
              auth.enabled = false;
            }
            // lib.neo.mkContainerDefinitions {
              # Built by this flake and loaded (and tagged ${name}:<hash>) by ${name}-image.service.
              ${name} = "${name}:${image.imageTag}";
              extraUnits = ["${name}-image"];
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
        description = "Portrait server configuration${plugin.label}";
      };
    };
}
