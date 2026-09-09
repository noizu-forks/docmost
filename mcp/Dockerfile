# Fork-local Dockerfile for the vendored docmost-mcp service (mcp/ subtree).
# Lives under mcp/ so upstream docmost never sees it (upstream-merge hygiene).
FROM elixir:1.18-alpine AS build

WORKDIR /app
ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY config ./config
COPY lib ./lib

RUN mix compile
RUN mix release

FROM elixir:1.18-alpine AS runtime

WORKDIR /app
COPY --from=build /app/_build/prod/rel/docmost_mcp ./

# Streamable HTTP edge (session-identity auth via DOCMOST_APP_SECRET);
# stdio is for local CLI use and is off in the container.
ENV DOCMOST_MCP_STDIO=false \
    DOCMOST_MCP_HTTP=true \
    DOCMOST_MCP_HTTP_PORT=4000

EXPOSE 4000
CMD ["bin/docmost_mcp", "start"]
