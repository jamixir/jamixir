ARG EX_VSN=1.17.3
ARG OTP_VSN=26.2.5.16
ARG BUILDER_IMG="hexpm/elixir:${EX_VSN}-erlang-${OTP_VSN}-ubuntu-jammy-20251001"
ARG RUNNER_IMG="ubuntu:jammy"

# A minimal Elixir image (Debian-based for gcc) as the builder
FROM ${BUILDER_IMG} AS builder

WORKDIR /node

# Set environment variables
ENV MIX_ENV="tiny"
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

# Copy mix files and fetch dependencies
COPY mix.exs mix.lock ./

# Use SSH for private repo access and fetch dependencies
RUN --mount=type=secret,id=ssh_key \
    mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
    cp /run/secrets/ssh_key ~/.ssh/id_rsa && \
    chmod 600 ~/.ssh/id_rsa && \
    ssh-keyscan github.com >> ~/.ssh/known_hosts && \
    echo "Host github.com\n  IdentityFile ~/.ssh/id_rsa\n  StrictHostKeyChecking no" > ~/.ssh/config && \
    mkdir -p ~/.cargo && \
    echo '[net]' > ~/.cargo/config.toml && \
    echo 'git-fetch-with-cli = true' >> ~/.cargo/config.toml && \
    mix local.hex --if-missing --force && \
    mix local.rebar --force && \
    mix deps.get --only $MIX_ENV

# Compile dependencies (including NIFs with Rust/Cargo)
RUN mix deps.compile

# Copy native code for NIF compilation
COPY native/ ./native/

# Copy NIF wrapper modules
COPY lib/util/ring_vrf.ex ./lib/util/ring_vrf.ex
COPY lib/util/crypto/ ./lib/util/crypto/
COPY lib/codec/erasure_coding.ex ./lib/codec/erasure_coding.ex


COPY lib/pvm/native.ex lib/pvm/native.ex

RUN mix compile

# Copy rest of application code
COPY . .

# Compile application (deps and NIFs already compiled)
RUN mix compile

# Create release
RUN mix release

RUN rm -f ~/.ssh/id_rsa

# Minimal runtime image
FROM ${RUNNER_IMG} AS runtime

# Install minimal running system dependencies
RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses5 locales libsqlite3-0 \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR /node
RUN chown nobody /node

ENV MIX_ENV="tiny"

# Copy the release built in the builder stage
COPY --from=builder --chown=nobody:root /node/_build/${MIX_ENV}/rel/jamixir /node/jamixir

# Copy default keys into the image
COPY --chown=nobody:root test/keys /node/keys
COPY --chown=nobody:root priv/genesis.json /node/
COPY --chown=nobody:root priv/polkajam_chainspec.json /node/

USER nobody

CMD ["/node/jamixir/jamixir", "run"]
