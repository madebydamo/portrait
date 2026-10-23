# Portrait-server binary and its OCI image (nix2container).
# The image tag is the image's Nix hash, so a changed image gets a new tag.
{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    n2c = inputs.nix2container.packages.${system}.nix2container;

    server = pkgs.rustPlatform.buildRustPackage {
      pname = "portrait-server";
      version = "0.1.0";
      src = ../../server;
      cargoLock.lockFile = ../../server/Cargo.lock;
    };

    # Everything the sandboxed shell can run. The sandbox PATH includes /bin.
    tools = pkgs.buildEnv {
      name = "portrait-tools";
      paths = with pkgs; [
        bashInteractive
        bash-completion
        coreutils
        util-linux # prlimit, setpriv
        bubblewrap
        iptables
        gnugrep
        gnused
        gawk
        findutils
        diffutils
        gzip
        gnutar
        less
        which
        procps
        ncurses
        curl
        cacert
        cowsay
        fortune
        figlet
        toilet
        lolcat
        sl
      ];
      pathsToLink = ["/bin" "/etc" "/share"];
    };

    # Kept apart from `root`: /etc also comes from `tools`, and nix2container
    # refuses a directory that two copyToRoot paths give different perms.
    etc = pkgs.runCommand "portrait-etc" {} ''
      mkdir -p $out/etc/portrait
      cat > $out/etc/passwd <<EOF
      root:x:0:0:root:/root:/bin/sh
      damo:x:999:999::/home/damo:/bin/false
      nobody:x:65534:65534:nobody:/nonexistent:/bin/false
      EOF
      cat > $out/etc/group <<EOF
      root:x:0:
      damo:x:999:
      nogroup:x:65534:
      EOF
      cp ${../../scripts/resolv.sandbox.conf} $out/etc/portrait/resolv.sandbox.conf
    '';

    root = pkgs.runCommand "portrait-root" {} ''
      mkdir -p $out/usr/local/bin $out/home/damo $out/tmp $out/run
      install -m755 ${../../scripts/apply-sandbox-fw.sh} $out/usr/local/bin/apply-sandbox-fw.sh
      install -m755 ${../../scripts/entrypoint.sh} $out/usr/local/bin/portrait-entrypoint.sh
      cp ${server}/bin/server $out/home/damo/server
      cp -r ${../../www} $out/home/damo/www
    '';

    image = n2c.buildImage {
      name = "portrait-server";
      copyToRoot = [tools etc root];
      # Tools rarely change; keep them in their own layer apart from server + www.
      layers = [(n2c.buildLayer {deps = [tools];})];
      perms = [
        {
          path = root;
          regex = "/home/damo.*";
          mode = "0755";
          uid = 999;
          gid = 999;
          uname = "damo";
          gname = "damo";
        }
        {
          path = root;
          regex = "/tmp";
          mode = "1777";
        }
      ];
      config = {
        Cmd = ["/usr/local/bin/portrait-entrypoint.sh"];
        WorkingDir = "/home/damo";
        Env = [
          "PATH=/usr/local/bin:/bin"
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        ];
      };
    };
  in {
    packages = {
      portrait-server = server;
      portrait-server-image = image;
    };
  };
}
