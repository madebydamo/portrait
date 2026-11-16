# Portrait-server service options.
{withSystem, ...}: {
  neoPlugin.modules.portrait-server-option = {
    config,
    lib,
    pkgs,
    plugin,
    ...
  }:
    with lib;
    with {inherit (lib.neo) mkOption mkEnableOption;}; let
      name = plugin.name "portrait-server";
      cfg = config.neo.services.${name};
      image = withSystem pkgs.stdenv.hostPlatform.system ({config, ...}: config.packages.portrait-server-image);
    in {
      options.neo.services.${name} = mkOption {
        type = types.submodule {
          options =
            {
              enabled = mkEnableOption "Your CV as a website that works like a terminal${plugin.label}" {rank = 0;};
              # TELEGRAM_BOT_TOKEN, through neo.core.secrets.containerEnv.
              telegramBotToken = lib.neo.mkSecretOption {
                type = types.nullOr types.str;
                default = null;
                rank = 10;
                description = "Key of the Telegram bot that forwards visitors' messages to you. Empty turns the message command off.";
                ui = lib.neo.ui.mkUi {label = "Telegram bot token";};
              };
              # TELEGRAM_CHAT_ID (not a secret).
              telegramChatId = mkOption {
                type = types.nullOr types.str;
                default = null;
                rank = 11;
                description = "Your Telegram chat that receives the messages visitors send with the message command. Empty turns the command off.";
                ui = lib.neo.ui.mkUi {
                  label = "Telegram chat ID";
                  visibleWhen = "telegramBotToken";
                };
              };
              # ROCKET_PORT. Copies behind the VPN share one network namespace,
              # so a second copy needs its own port.
              port = mkOption {
                type = types.port;
                default = 7999;
                rank = 80;
                description = "Port the site listens on inside its container. Change it only when two copies run behind the VPN.";
                ui = lib.neo.ui.mkUi {
                  label = "Site port";
                  group = lib.neo.ui.groups.advanced;
                };
              };
              # NEO_METRICS_PORT, set only while the monitoring agent collects.
              # Behind the VPN every routed app shares one network namespace,
              # so this port is claimed in vpn.ports like the site port.
              metricsPort = mkOption {
                type = types.port;
                default = 9464;
                rank = 81;
                description = "Port the monitoring numbers are served on inside the container. Change it only when another app behind the VPN uses the same one.";
                ui = lib.neo.ui.mkUi {
                  label = "Monitoring port";
                  group = lib.neo.ui.groups.advanced;
                };
              };
            }
            // lib.neo.mkVpnOptions {
              containers = [name];
              networks = [(lib.neo.docker.serviceNetwork name)];
              # Every routed container binds in gluetun's namespace: claim the
              # site port, and the metrics port while it is served.
              ports = [cfg.port] ++ optional config.neo.monitoring.collecting cfg.metricsPort;
              enabled = true;
            }
            // lib.neo.mkReverseProxyOptions {
              subdomain = plugin.name "portrait";
              # A public CV site: no login in front of it.
              auth.enabled = false;
            }
            // lib.neo.mkContainerDefinitions {
              # Built by this flake and loaded (and tagged ${name}:<hash>) by ${name}-image.service.
              ${name} = "${name}:${builtins.unsafeDiscardStringContext image.imageTag}";
              extraUnits = ["${name}-image"];
            }
            // lib.neo.mkServiceMeta {
              category = "Other";
              icon = ./icon.svg;
              tagline = "Your CV as a website that works like a terminal${plugin.label}";
              description = ''
                A personal CV and portfolio site that looks and works like a computer terminal.
                Visitors type commands such as whoami, projects or contact to read about you, can try real shell commands for fun, and can send you a short message.
              '';
              notes = ''
                Public on purpose: there is no login in front of it.
                Commands other than the portfolio pages run for real, each in a locked-down sandbox: 5 s of CPU, 128 MiB of memory, 10 s at most, no access to the server or other apps, and internet only through the VPN (without the VPN, internet commands such as curl fail).
                Commands are limited per visitor (about one per second, with short bursts) and to 8 sandboxes at once; extra ones get "slow down" or "busy".
                The message command sends the visitor's text to your Telegram chat, at most 5 per visitor and 50 in total per day. Leave the bot token empty to turn it off.
                The server process runs as root with network admin rights inside the VPN's network, which it shares with every other app behind the VPN. It needs them for the sandbox firewall; a flaw in the server could affect the VPN of those apps, so keep the plugin up to date.
                The server log keeps visitors' addresses and the commands they type (never their messages) as long as the monitoring logs are kept.
                Pages and texts are built into the image from the plugin's source, so changing them means changing the plugin.
              '';
              replaces = ["Linktree" "about.me"];
              privacy = [];
              projectUrl = "https://damianmoser.ch/";
              githubUrl = "https://github.com/madebydamo/portrait";
              # The repository has no LICENSE file yet.
              license = {
                spdx = "NONE";
                url = "https://github.com/madebydamo/portrait";
                openSource = false;
                note = "The code is public on GitHub but has no license yet, so others may not reuse it.";
              };
            }
            // lib.neo.mkSkillOptions {};
        };
        default = {};
        description = "Portrait server configuration${plugin.label}";
      };
    };
}
