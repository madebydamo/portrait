# Portrait-server service options.
{withSystem, ...}: {
  flake.modules.nixos.portrait-server-option = {
    config,
    lib,
    pkgs,
    ...
  }:
    with lib; let
      image = withSystem pkgs.stdenv.hostPlatform.system ({config, ...}: config.packages.portrait-server-image);
    in {
      options.neo.services.portrait-server = mkOption {
        type = types.submodule {
          options =
            {
              enabled = mkEnableOption "portrait-server service";
              # Secret option (Neo secrets): masked in the web UI; with an
              # encrypted config the value is a placeholder that is filled
              # in at activation (see default.nix). Older Neo without
              # mkSecretOption: a plain option.
              telegramBotToken = (lib.neo.mkSecretOption or mkOption) {
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
              ports = [7999];
              enabled = true;
            }
            // neo.mkReverseProxyOptions {
              subdomain = "portrait";
              auth.enabled = false;
            }
            // lib.neo.mkContainerDefinitions {
              # Built by this flake and loaded by portrait-server-image.service.
              portrait-server = image.imageRefUnsafe;
              extraUnits = ["portrait-server-image"];
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
