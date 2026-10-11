# Reproducible cross-arch build for the vendored docmost-mcp sidecar.
#
# WHY CROSS-ARCH: the cluster runs this image on amd64, but building a full
# amd64 BEAM stack under Rosetta on the arm64 dev boxes is not viable —
# OTP 28 fails to boot and OTP 27/26 segfault inside `mix`. So:
#
#   * build stage runs NATIVELY on arm64 (--platform=linux/arm64 pins it),
#   * `releases: [docmost_mcp: [include_erts: false]]` in mix.exs keeps the
#     release arch-independent (project + deps + Elixir bytecode, no ERTS),
#   * the runtime stage is amd64 and supplies its own OTP from the base image.
#
# Both stages use the SAME hexpm exact-version tag so the OTP build matches
# to the patch level on both arches. (Official `elixir:` tags skew per-arch —
# we saw arm64 kernel-10.2.7.5 vs amd64 kernel-10.2.7.4, which breaks the
# boot script's versioned paths.) If you bump the tag, bump it in BOTH stages
# and in nothing else.
#
# BUILD + TAG (from the fork root, docker context = mcp/):
#
#   docker --context orbstack build --platform linux/amd64 \
#     -f mcp/Dockerfile \
#     -t ops.noizu.com/docmost.noizu.com/mcp:sha-<forksha> mcp/
#
# <forksha> = short SHA of the fork commit being released (the sha-* tag the
# cluster sidecar runs).
#
# SMOKE (REQUIRED, exec the image — do NOT trust `docker manifest inspect`:
# a wrong-arch release passes manifest checks and still dies at boot):
#
#   docker --context orbstack run --rm --platform linux/amd64 \
#     ops.noizu.com/docmost.noizu.com/mcp:sha-<forksha> sh -c 'elixir --version'
#
# Must print the Elixir version with no `load_failed` / beam.smp crash.
FROM --platform=linux/arm64 hexpm/elixir:1.18.4-erlang-27.3.4.16-alpine-3.22.5 AS build

WORKDIR /app
ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix deps.get

COPY config ./config
COPY lib ./lib

RUN mix compile
RUN mix release

FROM --platform=linux/amd64 hexpm/elixir:1.18.4-erlang-27.3.4.16-alpine-3.22.5 AS runtime

WORKDIR /app
COPY --from=build /app/_build/prod/rel/docmost_mcp ./
# The cross-built release (include_erts: false) ships only project + deps +
# Elixir bytecode. Link this image's own (amd64) OTP apps into the release so
# the boot script finds kernel/stdlib/crypto/etc. — versions match exactly
# because the build stage uses the same base tag.
RUN for d in /usr/local/lib/erlang/lib/*; do n=$(basename "$d"); [ -e "lib/$n" ] || ln -s "$d" "lib/$n"; done

# Streamable HTTP edge (session-identity auth via DOCMOST_APP_SECRET);
# stdio is for local CLI use and is off in the container.
ENV DOCMOST_MCP_STDIO=false \
    DOCMOST_MCP_HTTP=true \
    DOCMOST_MCP_HTTP_PORT=4000

EXPOSE 4000
CMD ["bin/docmost_mcp", "start"]
