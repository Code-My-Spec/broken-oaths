# Dockerfile for the Broken Oaths Phoenix app.
# Multi-arch: built by GitHub Actions for linux/amd64 (prod box) and
# linux/arm64 (Hetzner cax11 UAT box). Same two-stage shape as the other
# apps in the fleet (see the devops repo).

ARG ELIXIR_VERSION=1.19.4
ARG OTP_VERSION=28.1
ARG DEBIAN_VERSION=bookworm-20260223-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ---- Build stage ----
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl nodejs npm \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN git config --global http.version HTTP/1.1
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# sops, fetched here so the runtime stage needs no download tooling of its
# own. Replaces the old AWS SSM secrets fetch (BrokenOaths.Secrets.load!/1,
# removed from config/runtime.exs) — SOPS_AGE_KEY is now the only secret
# the deploy has to carry, decrypting envs/<env>.enc.env at boot instead
# of hitting SSM at runtime.
#
# `dpkg --print-architecture` prints amd64/arm64, matching sops' own
# release asset naming, so this follows the image's own architecture
# rather than assuming which box will run it.
ARG SOPS_VERSION=3.9.4
RUN curl -fsSL -o /usr/local/bin/sops \
      "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.$(dpkg --print-architecture)" && \
    chmod +x /usr/local/bin/sops && \
    sops --version --disable-version-check

# Copy all application code
COPY priv priv
COPY lib lib
COPY assets assets

# Copy runtime config and release overlays
COPY config/runtime.exs config/
COPY rel rel

# The encrypted environments travel inside the image, as release overlays.
# The key does not: it arrives as SOPS_AGE_KEY at run time, so an image
# somebody pulls without the key is ciphertext and nothing else.
COPY envs rel/overlays/envs

# Install npm dependencies (html-to-image for the feedback widget)
RUN cd assets && npm ci && cd ..

# Compile and build assets (tailwind/esbuild binaries via hex packages)
RUN mix assets.setup
RUN mix compile
RUN mix assets.deploy

# Build release
RUN mix release

# ---- Runner stage ----
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/broken_oaths ./

# sops, to decrypt that environment at boot. No download tooling in this
# stage — the builder already fetched it for this image's architecture.
COPY --from=builder /usr/local/bin/sops /usr/local/bin/sops

USER nobody

# bin/boot, not bin/server directly. The release reads its secrets from
# System env in config/runtime.exs, and nothing has put them there yet —
# the image carries the ciphertext (envs/<env>.enc.env) and the container
# carries the key (SOPS_AGE_KEY). bin/boot decrypts, then execs bin/server
# (which still migrates before serving — unchanged from before).
CMD ["/app/bin/boot"]
