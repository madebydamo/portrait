# Use the official Rust image as the base image
FROM rust:1.90 as builder

# Set the working directory
WORKDIR /home/damo

# Copy the Cargo.toml and Cargo.lock files
COPY server/Cargo.toml server/Cargo.lock ./

# Copy the source code
COPY server/src ./src

# Build the application
RUN cargo build --release

# Use a minimal base image for the final stage
FROM ubuntu:24.04 as sandbox

# Install necessary dependencies, sandbox tools, and fun packages
RUN apt-get update && apt-get install -y \
    ca-certificates \
    bubblewrap \
    util-linux \
    coreutils \
    cowsay \
    curl \
    fortune-mod \
    figlet \
    toilet \
    bash-completion \
    lolcat \
    sl && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/games:$PATH"
# Create a non-root user with fixed UID/GID
RUN useradd -r -u 999 -s /bin/false damo
RUN mkdir -p /home/damo

# Set the working directory
WORKDIR /home/damo

# Copy the built binary from the builder stage
COPY --from=builder /home/damo/target/release/server /home/damo/server

# Copy the www directory
COPY www ./www

# Change ownership to root to prevent modifications/deletions by damo
RUN chown -R damo:damo /home/damo && \
    chmod -R go-w /home/damo  # Remove write perms for group/other (redundant but explicit)

# Expose the port the app runs on
EXPOSE 8000

# Run the application as root
ENV ROCKET_PORT=7999 
CMD ["./server"]
