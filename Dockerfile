# syntax=docker/dockerfile:1
ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3.4.3
ARG DEBIAN_VERSION=bookworm-20250929-slim
ARG LITESTREAM_VERSION=0.5.9

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
RUN mix compile

COPY config/runtime.exs config/
COPY rel rel
RUN chmod +x rel/overlays/bin/server \
  && mix release

FROM ${RUNNER_IMAGE} AS final

ARG LITESTREAM_VERSION

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN curl -fsSL -o /tmp/litestream.tgz \
    "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-x86_64.tar.gz" \
  && tar -C /usr/local/bin -xzf /tmp/litestream.tgz \
  && rm /tmp/litestream.tgz \
  && chmod +x /usr/local/bin/litestream

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"
ENV PHX_SERVER="true"
ENV PORT="8080"
ENV DATABASE_PATH="/tmp/phixem.db"
ENV LITESTREAM_BIN="/usr/local/bin/litestream"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/phixem ./

USER nobody

CMD ["/app/bin/server"]
