ARG EX_VSN=1.17.3
ARG OTP_VSN=26.2.5.9
ARG DEB_VSN=bullseye-20250224-slim
ARG BUILDER_IMG="hexpm/elixir:${EX_VSN}-erlang-${OTP_VSN}-debian-${DEB_VSN}"
ARG RUNNER_IMG="debian:${DEB_VSN}"
ARG MIX_ENV=prod
ARG GH_TOKEN

# A minimal Elixir image (Debian-based for gcc) as the builder
FROM ${BUILDER_IMG} AS builder

# Re-declare build args that are needed in this stage
ARG GH_TOKEN
ARG MIX_ENV=prod

WORKDIR /node

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    bash \
    gcc \
    gcc-aarch64-linux-gnu \
    libc6-dev-arm64-cross \
    make \
    cmake \
    git \
    curl \
    openssl \
    libssl-dev \
    wget \
  && rm -rf /var/lib/apt/lists/*

# Build static OpenSSL 1.1.1w
RUN cd /tmp && \
    wget https://www.openssl.org/source/openssl-1.1.1w.tar.gz && \
    tar -xzf openssl-1.1.1w.tar.gz && \
    cd openssl-1.1.1w && \
    ./config --prefix=/opt/openssl-static no-shared no-tests && \
    make -j$(nproc) && \
    make install_sw && \
    cd / && rm -rf /tmp/openssl-1.1.1w*


ENV CARGO_HOME=/root/.cargo
ENV PATH="$CARGO_HOME/bin:$PATH"

# Install Rust using rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    /root/.cargo/bin/rustup default stable && \
    /root/.cargo/bin/rustup update stable && \
    /root/.cargo/bin/rustup target add aarch64-unknown-linux-gnu && \
    /root/.cargo/bin/rustup target add x86_64-unknown-linux-gnu

# Configure Cargo for cross-compilation
RUN echo "[target.aarch64-unknown-linux-gnu]" >> /root/.cargo/config.toml && \
    echo "linker = \"aarch64-linux-gnu-gcc\"" >> /root/.cargo/config.toml

# Copy mix files and fetch dependencies
COPY mix.exs mix.lock ./

# Set static OpenSSL environment variables
ENV OPENSSL_LIB_DIR=/opt/openssl-static/lib
ENV OPENSSL_INCLUDE_DIR=/opt/openssl-static/include
ENV OPENSSL_STATIC=yes
ENV MIX_ENV=${MIX_ENV}

# Configure git with token and install dependencies
RUN git config --global url."https://${GH_TOKEN}@github.com/".insteadOf "https://github.com/" && \
    git config --global user.email "docker@build.local" && \
    git config --global user.name "Docker Build" && \
    mix local.hex --if-missing --force && \
    mix local.rebar --force && \
    mix deps.get --only ${MIX_ENV}


RUN mix deps.compile

# Copy source and build
COPY . .
RUN mix compile
RUN mix release

# Export stage for CI to extract release
FROM scratch AS release-export
COPY --from=builder /node/_build/*/jamixir-*.tar.gz /

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

ENV MIX_ENV=${MIX_ENV}

# Copy the release built in the builder stage
COPY --from=builder --chown=nobody:root /node/_build/${MIX_ENV}/rel/jamixir /node/jamixir

USER nobody

CMD ["/node/jamixir/bin/jamixir", "start"]
