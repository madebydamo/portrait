FROM rust:1.90 AS builder
WORKDIR /home/damo
COPY server/Cargo.toml server/Cargo.lock ./
COPY server/src ./src
RUN cargo build --release

FROM ubuntu:24.04 AS sandbox
RUN apt-get update && apt-get install -y \
  ca-certificates \
  bubblewrap \
  util-linux \
  coreutils \
  iptables \
  cowsay \
  curl \
  fortune-mod \
  figlet \
  toilet \
  bash-completion \
  lolcat \
  sl && \
  rm -rf /var/lib/apt/lists/*

RUN useradd -r -u 999 -s /bin/false damo
RUN mkdir -p /home/damo
WORKDIR /home/damo

COPY --from=builder /home/damo/target/release/server /home/damo/server
COPY www ./www
COPY scripts/apply-sandbox-fw.sh /usr/local/bin/apply-sandbox-fw.sh
COPY scripts/entrypoint.sh /usr/local/bin/portrait-entrypoint.sh
COPY scripts/resolv.sandbox.conf /etc/portrait/resolv.sandbox.conf
RUN chmod 755 /usr/local/bin/apply-sandbox-fw.sh /usr/local/bin/portrait-entrypoint.sh && \
  chown -R damo:damo /home/damo && \
  chmod -R go-w /home/damo

CMD ["/usr/local/bin/portrait-entrypoint.sh"]
