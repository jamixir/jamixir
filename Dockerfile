# ─────────────────────────────────────────────────────────────────────────────
# ARGs
# ─────────────────────────────────────────────────────────────────────────────
ARG EX_VSN=1.17.3
ARG OTP_VSN=26.2.5.9
ARG DEB_VSN=bullseye-20250224-slim
ARG BUILDER_IMG="hexpm/elixir:${EX_VSN}-erlang-${OTP_VSN}-debian-${DEB_VSN}"
ARG RUNNER_IMG="debian:${DEB_VSN}"
ARG MIX_ENV=prod
ARG GH_TOKEN

# ─────────────────────────────────────────────────────────────────────────────
# Builder Stage
# ─────────────────────────────────────────────────────────────────────────────
FROM ${BUILDER_IMG} AS builder


ARG MIX_ENV
ARG GH_TOKEN

WORKDIR /node

# Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ cmake make \
    bash curl wget git \
    libssl-dev openssl \
    gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
 && rm -rf /var/lib/apt/lists/*

# Static OpenSSL 1.1.1w build
ENV OPENSSL_VERSION=1.1.1w
RUN cd /tmp && \
    wget https://www.openssl.org/source/openssl-1.1.1w.tar.gz && \
    tar -xvzf openssl-1.1.1w.tar.gz && \
    cd openssl-1.1.1w && \
    ./config enable-ec_nistp_64_gcc_128 shared --prefix=/opt/openssl-static && \
    make -j$(nproc) && \
    make install_sw

ENV OPENSSL_STATIC=yes
ENV OPENSSL_LIB_DIR=/opt/openssl-static/lib
ENV OPENSSL_INCLUDE_DIR=/opt/openssl-static/include

ENV CPPFLAGS="-I/opt/openssl-static/include"
ENV LDFLAGS="-L/opt/openssl-static/lib"

# Rust toolchain
ENV OPENSSL_NO_VENDOR=1
ENV PKG_CONFIG_ALLOW_CROSS=1
ENV CARGO_HOME=/root/.cargo
ENV PATH="$CARGO_HOME/bin:$PATH"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV LD_LIBRARY_PATH="/opt/openssl-static/lib:$LD_LIBRARY_PATH"

RUN rustup default stable && \
    rustup update stable && \
    rustup target add aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu


# Cross-compile config
RUN echo '[target.aarch64-unknown-linux-gnu]' >> /root/.cargo/config.toml && \
    echo 'linker = "aarch64-linux-gnu-gcc"' >> /root/.cargo/config.toml


# Install Elixir deps
COPY mix.exs mix.lock ./

# Install jamixir_vm dependency separately
RUN git config --global url."https://${GH_TOKEN}@github.com/".insteadOf "https://github.com/" && \
    git config --global user.name "Docker Build" && \
    git config --global user.email "docker@build.local" && \
    mix deps.get --only jamixir_vm && \
    mix deps.compile jamixir_vm && \
    git config --global --unset url."https://${GH_TOKEN}@github.com/".insteadOf || true

ENV MIX_ENV="${MIX_ENV}"
# Install other dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only ${MIX_ENV} && \
    mix deps.compile


# Copy and compile source
COPY . .

RUN RUSTFLAGS="-L /opt/openssl-static/lib" mix compile && mix release



# Step 2: Extract the tarball from the correct location
RUN cd /node/_build/${MIX_ENV} && \
    ls -la jamixir-*.tar.gz && \
    tar -xzf jamixir-*.tar.gz && \
    ls -la

# Step 3: Copy OpenSSL libraries to crypto module
RUN cd /node/_build/${MIX_ENV} && \
    find lib -name "crypto-*" -type d && \
    cp /opt/openssl-static/lib/libcrypto.so.1.1 lib/crypto-*/priv/lib/ && \
    cp /opt/openssl-static/lib/libssl.so.1.1 lib/crypto-*/priv/lib/ && \
    echo "Verifying OpenSSL libraries are in place:" && \
    ls -la lib/crypto-*/priv/lib/

# Step 4: Copy jamixir bin to jamixir.real
RUN cd /node/_build/${MIX_ENV} && \
    cp jamixir jamixir.real && \
    chmod +x jamixir.real

# Step 4: Copy wrapper script to release
RUN cd /node/_build/${MIX_ENV} && \
    echo "Copying wrapper script..." && \
    cp /node/priv/jamixir_wrapper.sh jamixir && \
    chmod +x jamixir && \
    echo "Wrapper script copied and made executable"

# Step 5: Repack the tarball
RUN cd /node/_build/${MIX_ENV} && \
    echo "Repacking tarball..." && \
    ORIGINAL_TAR=$(ls jamixir-*.tar.gz) && \
    echo "Original tarball name: $ORIGINAL_TAR" && \
    tar -czf jamixir-modified.tar.gz bin erts-* jamixir jamixir.real lib rel releases && \
    mv jamixir-modified.tar.gz "$ORIGINAL_TAR" && \
    echo "Final tarball:" && \
    ls -la jamixir-*.tar.gz

# Debug: Check what libraries the crypto module needs   
RUN ldd /node/_build/${MIX_ENV}/rel/jamixir/lib/crypto*/priv/lib/crypto.so || true

# Debug: Check if OpenSSL libraries made it into the release
RUN echo "Checking if OpenSSL libraries are in the release:" && \
    find /node/_build/${MIX_ENV}/rel/jamixir -name "libcrypto*" -o -name "libssl*" || echo "No OpenSSL libraries found in release"

# # Install wrapper as the new bin/jamixir
# RUN cd /node/_build/${MIX_ENV}/rel/jamixir/bin && \
#     cp jamixir jamixir.real && \
#     mv jamixir-wrapper jamixir

# Export stage for CI to extract release
FROM scratch AS release-export
COPY --from=builder /node/_build/*/jamixir-*.tar.gz /

# Minimal runtime image
FROM ${RUNNER_IMG} AS runtime

# Install minimal running system dependencies
RUN apt-get update -y \
&& apt-get install -y libstdc++6 libncurses5 locales \
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

CMD ["/node/jamixir/jamixir", "start"]
