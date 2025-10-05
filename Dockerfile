# Use the official Rust image as the base image
FROM rust:1.90 as builder

# Set the working directory
WORKDIR /app

# Copy the Cargo.toml and Cargo.lock files
COPY server/Cargo.toml server/Cargo.lock ./

# Copy the source code
COPY server/src ./src

# Build the application
RUN cargo build --release

# Use a minimal base image for the final stage
FROM ubuntu:24.04

# Install necessary dependencies (if any, like ca-certificates for HTTPS)
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -r -s /bin/false damo

# Set the working directory
WORKDIR /app

# Copy the built binary from the builder stage
COPY --from=builder /app/target/release/server /app/server

# Copy the www directory
COPY www ./www

# Change ownership to the non-root user
RUN chown -R damo:damo /app

# Switch to the non-root user
USER damo

# Expose the port the app runs on
EXPOSE 8000

# Run the application
CMD ["./server"]
