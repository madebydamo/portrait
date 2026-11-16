# Portrait metrics, dashboard and alerts (neo.monitoring.apps, docs/APP-TELEMETRY.md in Neo).
#
# The server (server/src/telemetry.rs) logs JSON lines and serves Prometheus
# metrics on $NEO_METRICS_PORT, set only while the monitoring agent collects:
#   neo_app_feature_used_total{feature}    run_command, tab_complete, send_message, open_page
#   neo_app_errors_total{component, kind}  every error log line
#   neo_app_build_info{version}
#   portrait_exec_total{command, result}   command: fixed allow-list or "other" ("compgen" = Tab
#                                          completion); result: ok|error|not_found|timeout|
#                                          firewall_lost|spawn_error
#   portrait_exec_duration_seconds{kind}   histogram, kind = shell|completion
#   portrait_exec_rejected_total{reason}   rate_limit|busy|too_long|sandbox_firewall
#   portrait_sandboxes_running
#   portrait_messages_total{result}        sent|empty|not_configured|rate_limited|telegram_error|network_error
#   portrait_page_views_total{page}        index, the portfolio pages, other
#   portrait_sandbox_fw_ok                 1 while the sandbox egress firewall is in place
#   portrait_sandbox_fw_repairs_total{result}
#
# With the VPN on, the container lives in gluetun's namespace; Neo scrapes
# gluetun on the service network for it.
{...}: {
  neoPlugin.modules.portrait-server-monitoring = {
    config,
    lib,
    plugin,
    ...
  }: let
    name = plugin.name "portrait-server";
    cfg = config.neo.services.${name};
    label = "Portrait${plugin.label}";
    sel = lib.neo.grafana.appSelector name;
    s = lib.neo.grafana.alertSelector name;
    # Typed commands only; "compgen" is Tab completion.
    typed = ''${sel}, command!="compgen"'';
    red = {
      mode = "absolute";
      steps = [
        {
          color = "green";
          value = null;
        }
        {
          color = "red";
          value = 1;
        }
      ];
    };
    fwMappings = [
      {
        type = "value";
        options = {
          "0" = {
            text = "OPEN";
            color = "red";
            index = 0;
          };
          "1" = {
            text = "Closed";
            color = "green";
            index = 1;
          };
        };
      }
    ];
  in {
    config = lib.mkIf cfg.enabled {
      virtualisation.oci-containers.containers.${name}.environment =
        lib.mkIf config.neo.monitoring.collecting {NEO_METRICS_PORT = toString cfg.metricsPort;};

      neo.monitoring.apps.${name} = {
        metrics.main = {
          container = name;
          port = cfg.metricsPort;
        };

        dashboards.overview = {
          title = label;
          description = "Who visits the CV site, which pages they open and commands they type, messages sent to you, and whether the command sandbox is locked down.";
          time = "now-7d";
          panels = with lib.neo.grafana;
            [
              (row "Portrait" null)
              (stat {
                title = "Visitors";
                w = 4;
                h = 4;
                description = "Different addresses that opened the site in the chosen time range.";
                datasource = loki;
                targets = [(lq ''count(sum by (ip) (count_over_time({job="swag", service="${name}"} | path="/" [$__range])))'' // {queryType = "instant";})];
                options.colorMode = "none";
              })
              (stat {
                title = "Pages opened";
                w = 4;
                h = 4;
                description = "The start page and portfolio pages (whoami, projects, …) served in the chosen time range.";
                targets = [(pq "round(sum(increase(portrait_page_views_total{${sel}}[$__range]))) or vector(0)" "")];
                decimals = 0;
                options.colorMode = "none";
              })
              (stat {
                title = "Commands run";
                w = 4;
                h = 4;
                description = "Shell commands visitors ran in the sandbox (without Tab completions).";
                targets = [(pq "round(sum(increase(portrait_exec_total{${typed}}[$__range]))) or vector(0)" "")];
                decimals = 0;
                options.colorMode = "none";
              })
              (stat {
                title = "Messages sent";
                w = 4;
                h = 4;
                description = "Messages visitors sent you that reached Telegram.";
                targets = [(pq ''round(sum(increase(portrait_messages_total{${sel}, result="sent"}[$__range]))) or vector(0)'' "")];
                decimals = 0;
                options.colorMode = "none";
              })
              (stat {
                title = "Timeouts";
                w = 4;
                h = 4;
                description = "Commands stopped after 10 seconds.";
                targets = [(pq ''round(sum(increase(portrait_exec_total{${sel}, result="timeout"}[$__range]))) or vector(0)'' "")];
                decimals = 0;
                thresholds = red;
              })
              (stat {
                title = "Sandbox firewall";
                w = 4;
                h = 4;
                description = "Closed: sandboxed commands reach only the internet through the VPN. OPEN: the firewall is missing and commands are refused until it is back.";
                targets = [(pq "min(portrait_sandbox_fw_ok{${sel}})" "")];
                mappings = fwMappings;
                thresholds = {
                  mode = "absolute";
                  steps = [
                    {
                      color = "red";
                      value = null;
                    }
                    {
                      color = "green";
                      value = 1;
                    }
                  ];
                };
              })
              (bargauge {
                title = "Top commands";
                w = 12;
                h = 9;
                description = "What visitors type, by the first word; unknown programs count as other.";
                targets = [(pq "sort_desc(round(sum by (command) (increase(portrait_exec_total{${typed}}[$__range]))))" "{{command}}")];
                decimals = 0;
              })
              (bargauge {
                title = "Pages";
                w = 12;
                h = 9;
                description = "Start page and portfolio pages opened.";
                targets = [(pq "sort_desc(round(sum by (page) (increase(portrait_page_views_total{${sel}}[$__range]))))" "{{page}}")];
                decimals = 0;
              })
              (timeseries {
                title = "Command time";
                w = 12;
                h = 8;
                description = "How long sandboxed commands take, from start to exit (Tab completions not included).";
                unit = "s";
                targets = [
                  (pq ''histogram_quantile(0.5, sum by (le) (rate(portrait_exec_duration_seconds_bucket{${sel}, kind="shell"}[$__rate_interval])))'' "median")
                  (pq ''histogram_quantile(0.95, sum by (le) (rate(portrait_exec_duration_seconds_bucket{${sel}, kind="shell"}[$__rate_interval])))'' "95th percentile")
                ];
              })
              (bars {
                title = "Command results";
                w = 12;
                h = 8;
                description = "ok, error (non-zero exit), not_found (no such program), timeout, firewall_lost (stopped because the firewall went missing).";
                targets = [(pq "sum by (result) (increase(portrait_exec_total{${typed}}[$__interval]))" "{{result}}")];
              })
              (bars {
                title = "Messages";
                w = 12;
                h = 8;
                targets = [(pq "sum by (result) (increase(portrait_messages_total{${sel}}[$__interval]))" "{{result}}")];
              })
              (bars {
                title = "Refused commands";
                w = 12;
                h = 8;
                description = "rate_limit: one visitor sent too many; busy: all sandboxes in use; too_long; sandbox_firewall: refused while the firewall was missing.";
                targets = [(pq "sum by (reason) (increase(portrait_exec_rejected_total{${sel}}[$__interval]))" "{{reason}}")];
              })
              (timeseries {
                title = "Sandboxes running";
                w = 12;
                h = 8;
                targets = [(pq "max(portrait_sandboxes_running{${sel}})" "running")];
                decimals = 0;
              })
              (stateTimeline {
                title = "Sandbox firewall";
                w = 12;
                h = 8;
                targets = [(pq "min by (host) (portrait_sandbox_fw_ok{${sel}})" "{{host}}")];
                mappings = fwMappings;
              })
              (logs {
                title = "Commands typed";
                w = 24;
                h = 10;
                targets = [(lq ''{job="journal", host=~"$host", unit="docker-${name}.service"} | json event="event" | event="exec"'')];
              })
            ]
            ++ lib.neo.grafana.app.features {service = name;}
            ++ lib.neo.grafana.app.web {service = name;}
            ++ lib.neo.grafana.app.errors {
              service = name;
              containers = [name];
              # The oneshot that loads the image into Docker.
              units = ["${name}-image"];
            };
        };

        alerts =
          lib.neo.monitoring.appAlerts {
            service = name;
            inherit label;
            containers = [name];
            units = ["${name}-image"];
          }
          // {
            sandbox-firewall = {
              title = "${label}: sandbox firewall missing";
              expr = ''min by (host) (portrait_sandbox_fw_ok{${s}})'';
              below = 1;
              for = "1m";
              severity = "critical";
              summary = "The firewall that keeps visitors' commands away from the server and the other apps behind the VPN is missing on {{ $labels.host }}, and Portrait could not put it back. Commands are refused until it is.";
            };
            exec-timeouts = {
              title = "${label}: many commands time out";
              expr = ''sum by (host) (increase(portrait_exec_total{${s}, result="timeout"}[15m]))'';
              above = 10;
              for = "0s";
              summary = "{{ printf \"%.0f\" $values.B.Value }} commands on the CV site hit the 10 second limit in 15 minutes: someone may be trying to overload it, or the VPN is slow.";
            };
            telegram-failing = {
              title = "${label}: messages do not reach Telegram";
              expr = ''sum by (host) (increase(portrait_messages_total{${s}, result=~"telegram_error|network_error"}[30m]))'';
              above = 0;
              for = "0s";
              summary = "{{ printf \"%.0f\" $values.B.Value }} messages from visitors could not be sent to your Telegram in the last 30 minutes. Check the Telegram bot token and chat ID.";
            };
          };
      };
    };
  };
}
