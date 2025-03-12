ARG EX_VSN=1.17.3
ARG OTP_VSN=26.2.5.9
ARG DEB_VSN=bullseye-20250224-slim
ARG BUILDER_IMG="hexpm/elixir:${EX_VSN}-erlang-${OTP_VSN}-debian-${DEB_VSN}"
ARG RUNNER_IMG="debian:${DEB_VSN}"

# A minimal Elixir image (Debian-based for gcc) as the builder
FROM ${BUILDER_IMG} AS builder

WORKDIR /node

# Set environment variables
ENV MIX_ENV="prod"
ENV CARGO_HOME=/root/.cargo
ENV PATH="$CARGO_HOME/bin:$PATH"

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    bash \
    gcc \
    make \
    cmake \
    git \
    curl \
    openssl \
    openssh-client \
  && rm -rf /var/lib/apt/lists/*

# Install Rust using rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    /root/.cargo/bin/rustup default stable && \
    /root/.cargo/bin/rustup update stable

# Enable SSH for GitHub to interact with private repos
RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh
RUN echo "Host github.com\n  StrictHostKeyChecking no\n  ForwardAgent yes" >> /root/.ssh/config
RUN ssh-keyscan github.com >> ~/.ssh/known_hosts

# Copy mix files and fetch dependencies
COPY mix.exs mix.lock ./

RUN --mount=type=ssh \
    mix local.hex --if-missing --force && \
    mix local.rebar --force && \
    mix do deps.get --only $MIX_ENV, deps.compile


# Copy node code and compile
COPY . .
RUN mix compile
RUN mix release

# Minimal runtime image
FROM ${RUNNER_IMG} AS runtime

# Install minimal running system dependencies
RUN apt-get update -y \
&& apt-get install -y libstdc++6 openssl libncurses5 locales \
&& apt-get clean && rm -f /var/lib/apt/lists/*_*

# set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR /node
RUN chown nobody /node

ENV MIX_ENV="prod"

# Copy the release built in the builder stage
COPY --from=builder --chown=nobody:root /node/_build/${MIX_ENV}/rel/jamixir /node/jamixir

USER nobody

CMD ["/node/jamixir/bin/jamixir", "start"]
