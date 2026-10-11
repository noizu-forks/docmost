# Test Health — docmost-mcp
_Last measured: 2026-10-07 · branch develop@46690c7_

Single `test` job, no services, no Docker image. The test suite itself runs in about 1s. CI time is
almost all compile time, so the compile step is what these changes target.

| Metric | Before | After |
|---|---|---|
| CI PR wall-clock — critical path (warm / cold) | 44–49s / 170s | see PR run |
| Main release build (warm / cold) | 23s / n.a. (no image; CI-only) | unchanged semantics |
| CI acceptance test job (warm / cold) | Test step 11s / 76s (incl. test-env compile) | see PR run |
| Local full-suite runtime (uptime load) | 0.8s ExUnit, 86s cold test compile (load ~24–42) | same |
| Docker build (warm / cold) | n.a. — repo has no Dockerfile | n.a. |
| Tests in acceptance / slow tier | 151 / 0 | 151 / 0 |
| Async modules / total | 4 / 17 (async 0.6s, sync 0.2s) | 4 / 17 |
| Coverage — acceptance pass | not run in CI (95.4% local) | 95.4% local, enforced in CI |
| Coverage — full pass | same as acceptance | same |
| Coverage gate | 85% in mix.exs, never enforced (CI ran plain `mix test`) | 90% (`floor(95.4) - 5`), enforced via `mix test --cover` |

What the old setup cost: the `Compile` step built the **dev** env and `mix test` then built the
**test** env, so a cold run compiled every dependency twice (76s + 76s). The job now sets
`MIX_ENV: test` for every step, so dependencies compile once. `--warnings-as-errors` still covers
`lib/` plus `test/support`.

## Caching status
- GitHub Actions: deps ✅ · build ✅ (one env now) · npm n.a. · .next/cache n.a. · PLT n.a. (no dialyzer) · develop-ref seeding ✅ (already ran on `push: develop`)
- Cache key now uses the `setup-beam` outputs (`otp-version`, `elixir-version`) and `**/mix.lock`; `concurrency` cancels superseded PR runs only.
- Docker: n.a. (no image built or pushed by this repo)

## Slow tests (tier: nightly)
None. The whole suite takes about 1s.

## Test debt
| Item | Kind | Notes |
|---|---|---|
| 13 of 17 modules are sync | sync-only | Most of them `Application.put_env` the client and config. The whole suite takes 1s, so flipping them to async isn't worth it. |
| Local runs re-lock deps | coverage gap (env drift) | When the monorepo's `Libs/ai/elixir-mcp` path dep is present, `mix deps.get` re-resolves and rewrites `mix.lock`, while CI uses hex `noizu_mcp`. Don't commit those lock changes. Set `NOIZU_MCP_PATH` deliberately. |

## Nightly
Not needed. There's no slow tier and no image to keep a release cache warm for. A cold main run
is a single compile, about 90s.
