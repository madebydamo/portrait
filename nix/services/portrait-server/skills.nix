# Hermes skill for Portrait (published as neo-<name>).
{...}: {
  neoPlugin.modules.portrait-server-skills = {
    config,
    lib,
    plugin,
    ...
  }: let
    name = plugin.name "portrait-server";
    cfg = config.neo.services.${name};
  in {
    config.neo.services.${name}.skill.conf = lib.neo.mkServiceSkill {
      service = name;
      inherit config;
      description = "Portrait: the owner's public CV site that works like a terminal, with sandboxed shell commands and a message-to-Telegram command";
      tags = ["neo" "portrait" "website" "cv"];
      title = "Neo · Portrait${plugin.label}";
      body = ''
        ## When to Use
        Questions about the CV/portfolio site, whether it is up, what visitors do on it, messages from visitors not arriving on Telegram, or the command sandbox and its firewall.

        ## Architecture notes
        - One container `${name}` (Rust/Rocket), image built by the plugin and loaded by the oneshot `${name}-image.service` before `docker-${name}.service`
        - Listens on port ${toString cfg.port} (setting `services.${name}.port`); public at the site's subdomain with no login (`auth.enabled = false` on purpose)
        - Network: its own Docker network `app-${name}`. With `services.${name}.vpn.enabled` (default true) the container runs in gluetun's (`vpn`) network namespace, shared with every other VPN-routed app; then `docker-vpn.service` must be running for the site to work
        - Portfolio pages (`whoami`, `projects`, `contact`, …) are static files; anything else a visitor types is `POST /execute`, run by `bash -c` inside prlimit + setpriv (uid 999, no capabilities) + bwrap, 10 s wall limit
        - Sandbox firewall: nftables table `inet portrait-sandbox` plus owner-match rules at the top of iptables OUTPUT. uid 999 may only use `tun0` (VPN) and DNS on 127.0.0.1:53. The server checks it before every command and every 5 s, reinstalls it, refuses commands (503) while it is missing and kills running sandboxes
        - Limits: about 1 command per second per visitor (burst 10) in the app, 2/s (burst 10) per address in SWAG, 8 sandboxes at once (429 "busy"), commands up to 4000 bytes
        - `message <text>` sends the text to Telegram: settings `services.${name}.telegramBotToken` (secret) and `services.${name}.telegramChatId`; at most 5 per visitor and 50 per day
        - Logs are JSON lines (`level`, `event`): `event=exec` per command (ip, command, result, ms, cmd), `event=message` (result, length; never the text), `event=sandbox_fw`, `event=exec_rejected`
        - Metrics on port ${toString cfg.metricsPort} inside the container while monitoring collects: `portrait_exec_total`, `portrait_messages_total`, `portrait_sandbox_fw_ok`, `neo_app_feature_used_total`

        ## Procedures
        1. Health: `systemctl status ${name}-image docker-${name}` (and `docker-vpn` when the VPN is on)
        2. Recent problems: `docker logs ${name} --tail 200 2>&1 | grep -E '"level":"(error|critical|warning)"'`
        3. Sandbox firewall: `docker exec ${name} /usr/local/bin/apply-sandbox-fw.sh --check; echo $?` (0 = complete, 2 = only the iptables layer missing, still closed, 1 = open). Details: `docker exec ${name} nft list table inet portrait-sandbox` and `docker exec ${name} iptables -S OUTPUT | grep portrait-sandbox`
        4. Messages not arriving: `docker logs ${name} 2>&1 | grep '"event":"message'` and check the `result` (`not_configured` = token or chat ID empty, `telegram_error` = Telegram refused, see `exc`, `network_error` = no internet / VPN down)
        5. Try a command like a visitor: `docker exec ${name} curl -sS -H 'Content-Type: application/json' -d '{"command":"echo hi"}' http://127.0.0.1:${toString cfg.port}/execute`
        6. Restart: `systemctl restart docker-${name}`

        ## Pitfalls
        - Never run visitors' commands outside the sandbox, and never turn the firewall off: the server runs as root with NET_ADMIN in the namespace every VPN-routed app shares
        - Pages and texts are part of the image; changing them means changing the plugin repository
        - With the VPN off, commands that need the internet (curl) fail by design

        ## Verification
        - `docker-${name}` is active, `apply-sandbox-fw.sh --check` exits 0
        - `GET https://<subdomain>.<domain>/` returns 200 without a login
        - `POST /execute {"command":"echo hi"}` returns `{"stdout":"hi…","status":0}`
      '';
    };
  };
}
