# Use Debian-based Elixir image instead of Alpine
FROM elixir:1.17.3

# Set environment variables
ENV MIX_ENV=prod

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential git \
    cmake libssl-dev \
    numactl libnuma-dev \
    perl-base perl-modules \
    libatomic1 \
    && rm -rf /var/lib/apt/lists/*

# Fixing missing libatomic.so and libnuma.so
RUN ln -s /usr/lib/x86_64-linux-gnu/libatomic.so.1 /usr/lib/libatomic.so
RUN ln -s /usr/lib/x86_64-linux-gnu/libnuma.so.1 /usr/lib/libnuma.so.1

# Create a non-root user with the same UID/GID as the host user
ARG USER_ID
ARG GROUP_ID

# Create the user and group with fallback to defaults if not provided
RUN groupadd -g ${GROUP_ID:-1000} jamixir && \
    useradd -u ${USER_ID:-1000} -g jamixir -m jamixir

# Switch to non-root user so rustup installs for that user
USER jamixir

# Install rustup and the stable Rust toolchain (which will be 1.75.0+)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable

# Add cargo binaries to PATH
ENV PATH="/home/jamixir/.cargo/bin:${PATH}"

# Create and set the working directory
WORKDIR /app

# # Install Hex and Rebar
# RUN mix local.hex --force && \
#     mix local.rebar --force

# # Fetch the project dependencies
# RUN mix deps.get --only prod

# # Copy the rest of the application code
# COPY . .

# # Compile the project
# RUN mix compile

# # Set the entry point for the application
# CMD ["mix", "cli"]
