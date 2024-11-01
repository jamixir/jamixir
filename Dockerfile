# Use the official Elixir image as the base image
FROM elixir:1.17.3-alpine

# Set environment variables
ENV MIX_ENV=prod

# Install build dependencies
RUN apk add --no-cache build-base git

# Install Rust and Cargo
RUN apk add --no-cache rust cargo

# Create and set the working directory
WORKDIR /app

# Copy the mix.exs and mix.lock files
COPY mix.exs mix.lock ./

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Fetch the project dependencies
RUN mix deps.get --only prod

# Copy the rest of the application code
COPY . .

# Compile the project
RUN mix compile

# Set the entry point for the application
CMD ["mix", "cli"]