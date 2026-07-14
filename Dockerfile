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
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy all application code
COPY priv priv
COPY lib lib
COPY assets assets

# Copy runtime config and release overlays
COPY config/runtime.exs config/
COPY rel rel

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

USER nobody

CMD ["/app/bin/server"]
