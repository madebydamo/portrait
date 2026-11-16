# Portrait-server reverse proxy configuration for SWAG.
# Public site (no tinyauth). /execute runs visitors' commands, so it gets a
# per-address rate limit here on top of the server's own limits.
{...}: {
  neoPlugin.modules.portrait-server-swag = {
    config,
    lib,
    plugin,
    ...
  }: let
    name = plugin.name "portrait-server";
    cfg = config.neo.services.${name};
    # One zone per copy; nginx zone names stay plain.
    zone = "${builtins.replaceStrings ["-"] ["_"] name}_exec";
    # Same JSON shape as the server's answers, so the page shows the reason.
    slowDown = builtins.toJSON {
      stdout = "";
      stderr = "Slow down a little: too many commands, try again in a few seconds";
      status = 1;
    };
  in {
    # limit_req_zone sits outside `server {}`: proxy-confs are included at
    # the http level.
    config.neo.services.${name}.proxyConf = lib.mkDefault (''
        limit_req_zone $binary_remote_addr zone=${zone}:1m rate=2r/s;

      ''
      + lib.neo.mkSubdomainProxyConf {
        inherit config cfg;
        upstream = name;
        port = cfg.port;
        # JSON commands and messages only; the server caps a command at 4000 bytes.
        maxBodySize = "64k";
        extraLocations = ''
          location = /execute {
            limit_req zone=${zone} burst=10 nodelay;
            limit_req_status 429;
            error_page 429 = @${zone}_slow;
          ${lib.neo.swagUpstream {
            app = name;
            port = cfg.port;
          }}
          ${lib.neo.authBlock config cfg}
          }
          location @${zone}_slow {
            default_type application/json;
            return 429 '${slowDown}';
          }
        '';
      });
  };
}
