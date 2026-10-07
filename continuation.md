# CONTINUATION — Docmost Fork Program (community API v1 + MCP service)

> Resume prompt for the next session. Read top-to-bottom before acting.
> Written 2026-09-07 during a live multi-agent session; amend with agent wrap-up notes at the bottom.

## Mission (user's goal, still active)

Debug/finesse/enhance until the **API and MCP work perfectly e2e**, ultimately serving **docmost.noizu.com**; pre-release testing happens in a **local sandbox** (compose stack; DB via read-only snapshot of prod, restored into sandbox postgres — never mutable against prod). Coverage mandate: **≥85% unit coverage on both** the community API (jest) and the MCP service (Elixir).

Background: deployed docmost.noizu.com has NO Enterprise license → stock EE API keys impossible. Owner pivoted: fork docmost, build a community API + vendored MCP service, run locally now, cluster-deploy later.

## Repos / branches / state of record

**Fork: `noizu-forks/docmost`** (public, AGPL-3.0; `packages/ee` = license file ONLY — EE code is a private submodule, never derive from it).
Local clone: `staging/docmost-fork` (upstream `main` @ `0a87db4f`, ahead of v0.95.0 — state base commit in PRs).

| Branch | Tip (verify with git log) | PR | Contents |
|---|---|---|---|
| `feature/community-api` | `4a0a583d`+ (fixes landing) | [fork PR #1](https://github.com/noizu-forks/docmost/pull/1) | Community API v1: `/api/v1` resource REST (spaces/pages/share-upsert/access-grants/search/keys), `{data,meta.nextCursor}` envelope, V1ExceptionFilter, stable grant ids, server-computed publicUrl. Exactly 3 upstream files touched: `jwt.strategy.ts` (EE-first→community fallback), `page.service.ts` (+updatedAt sidebar select), `app.module.ts` (CommunityModule). |
| `feature/mcp-service` | `6bc1866c`+ | [fork PR #2](https://github.com/noizu-forks/docmost/pull/2) | `mcp/` subtree (docmost-mcp@develop @ `8c4072e`) + `docker-compose.mcp.yml` override (Caddy edge `:80`, `/mcp*`→mcp:4000 unrewritten streaming-safe, `/*`→docmost:3000) + session-identity auth (verify authToken JWT HS256 w/ shared APP_SECRET=DOCMOST_APP_SECRET, forward as Bearer; static key only behind `DOCMOST_MCP_ALLOW_STATIC_KEY=1`). ZERO upstream files. `FORK.md` has subtree-sync procedure. |
| `local/e2e` (DISPOSABLE, never push) | `68bba4fc` | — | local integration of both branches for sandbox testing. |
| docmost-mcp `feature/v1-api-client` | `9a12688` | [docmost-mcp PR #3](https://github.com/noizu-labs/docmost-mcp/pull/3) (→develop) | Client rewritten to v1 contract; 22→102 tests; **93.74% coverage, 85% gate wired** (`mix.exs` `test_coverage: [summary: [threshold: 85]]` — threshold MUST sit under `summary:` on Elixir 1.18.4). |

**Worktrees (canonical convention `.claude/worktrees/<branch>`):**
- `staging/docmost-fork/.claude/worktrees/feature-community-api` (API fixes + coverage work — was mid-spec-edit-batch at wrap-up)
- `staging/docmost-fork/.claude/worktrees/feature-mcp-service`
- `/Users/keithbrings/Work/Space/Noizu/Portfolio/Apps/AI/docmost-mcp/.claude/worktrees/feature-v1-api-client`

**Specs (authoritative contract):**
- `staging/community-api-v1-spec.md` — §1 endpoint table IS the contract; §0 ten binding design principles.
- `staging/mcp-integration-spec.md` — subtree/compose/session-auth.

**Hand-off artifacts (being written at wrap-up — verify existence):**
- `staging/e2e-sandbox-state.md` — stack up/down commands, port overrides for independent stacks, dump restore, admin-user + key-mint procedure.
- `staging/docmost-sandbox.dump` — pg_dump -Fc of prod docmost DB (exists, ~166 KB, chmod 600, 62 tables verified; taken via svc/platform-timescaledb forward — platform-postgres is ExternalName, not directly forwardable).

## Sandbox state at wrap-up

- Compose project `docmost-e2e` (in `staging/docmost-fork`): `docmost-e2e-docmost-1`, `-db-1`, `-redis-1`, `-proxy-1`, `-mcp-1` were UP (db/redis/proxy 3h+, mcp recently rebuilt). Stack = `docker compose -f docker-compose.yml -f docker-compose.mcp.yml`.
- Prod data restored into sandbox postgres from snapshot (read-only `pg_dump` over port-forward to platform-postgres, ns `platform`, ctx `noizu`, creds via Infisical/dc — NEVER print secrets).
- Sandbox admin user `sandbox-e2e@local` (password reset directly in the sandbox DB); `POST /api/v1/keys` mints keys with its session.
- ⚠️ Fork is AHEAD of deployed v0.95.0 and runs migrations on boot → NEVER point a mutable connection at prod DB; snapshot-restore only.

## Verified so far

- Fork PR #2 live container smoke: 401 unauth / bad token; valid session JWT → full MCP `initialize` round-trip via `{site}/mcp`. 40/40 mcp tests.
- Client: 102 tests green (93.74% cov). Unit contract fully asserted.
- e2e loop bugs FIXED en route (all pushed to PR branches): mcp share+page-access mutations over v1 surface; client pagination nextCursor loop-guard false positive (multi-page listing was broken); dead `params == []` branch in req.ex; TestClient teardown race; server: global response envelope intercepting v1 (bypass), markdown-default on page create, 404 malformed key ids.
- Fork PR #1: 54/54 unit tests, tsc+eslint clean, e2e harness env-gated. Coverage sweep to 85% IN PROGRESS at wrap-up (check `feature-community-api` worktree status + PR #1 for the final push).

## Remaining work (in order)

1. **Finish coverage-api → ≥85%** (jest, scoped config `apps/server/src/community/jest.config.js`, upstream files untouched). If incomplete: see agent wrap-up note below for exact remaining gaps.
2. **Resume the e2e sandbox loop** (use `staging/e2e-sandbox-state.md`): full `/api/v1` contract walk → MCP VFS flow (spaces→read→create→share→meta) → live client run vs sandbox → fix at source (API fixes → `feature-community-api` worktree; MCP fixes → `feature-mcp-service`; client fixes → `feature-v1-api-client`), push, rebuild, repeat until the matrix is fully green.
3. **Parallel split (owner asked for it)**: independent stacks per stream via `COMPOSE_PROJECT_NAME` + port overrides in the state file — API stream (app direct, no proxy) and MCP stream (full override) in parallel.
4. **Merge gate (USER-GATED — classifier blocks agent merges; needs fresh in-chat consent):** fork PR #1 → #2 (zero overlap), then docmost-mcp PR #3 → develop. Then re-run the e2e gate against merged `main`.
5. **Subtree sync caveat:** after PR #3 merges, `git subtree pull` will conflict in `mcp/lib/docmost_mcp/client/req.ex` + `config.ex` (fork session-auth hunks vs client v1 hunks) — resolve carefully.
6. **Phase D (parked):** deploy fork to cluster as docmost.noizu.com (chart/terraform under `terraform/kubernetes/platform/content/`, image `docmost/docmost:latest` today). Not started — needs owner go.

## Safety rules (standing)

- Never print/echo secrets (DB creds, JWTs, APP_SECRET, password hashes, license keys).
- Prod DB: read-only pg_dump via port-forward ONLY; no mutations, kill port-forwards after.
- Never merge PRs without fresh in-chat user consent; PRs auto-update on branch push.
- Monorepo root (`trl-infra`): no branch/worktree/fork. Submodule/fork worktrees at `.claude/worktrees/<branch>`.
- `staging/` is local-only, gitignored — never push it.
- `local/e2e` is disposable — never push.
- tobor-sessions MCP unavailable → proceeding without registration (pre-authorized by owner).

---

## Agent wrap-up notes (FINAL — session parked 2026-09-07/08 by owner order)

- **All agents stopped by explicit owner order.** A brief goal-hook auto-resume (coverage-api-resume, e2e-matrix) was killed before landing any changes — no stray state; verified: all three worktrees clean, all branches pushed. Do NOT resume agents without the owner explicitly asking.
- coverage-mcp: DONE — 93.74% coverage + 85% gate (mix.exs `test_coverage: [summary: [threshold: 85]]`), 2 prod bugs fixed (pagination nextCursor loop-guard, dead req.ex branch), 102 tests green, tip `9a12688` on `feature/v1-api-client` (PR #3).
- coverage-api: final % UNMEASURED — WIP was landed green before shutdown: commits `7b336d98` + `b505a44b` on `feature/community-api` (118 tests green, tsc clean at land time). Resume step: `cd apps/server && npx jest -c src/community/jest.config.js --coverage`, close gaps to 85 lines+branches (add coverageThreshold to the scoped config).
- e2e matrix: NEVER COMPLETED. Sandbox stack `docmost-e2e` was left running (may be stale after restarts — rebuild via state file). Resume step 2 of §Remaining work. Bugs already fixed on branches: envelope-bypass, markdown-default, 404 malformed key ids, mcp share/access mutations, client pagination loop-guard.
- Owner's last standing instructions (supersede the goal hook): park the program; three PRs pushed and open is the deliverable; no test runs needed. Merge + deploy remain owner-gated.

---

## 2026-09-10 wrap-up — program delivered through the merge gate (owner-directed resume)

- **PRs MERGED:** fork #1 (community-api) + #2 (mcp-service) → `main` @ `ef4985ee`; docmost-mcp #3 (v1 client) → `develop` @ `9c4a974`. Fork `develop` synced with main (`10197f34`), then subtree sync landed (`3a1b0b50`, pushed).
- **Landed fixes:** API content-format fixes `ff1e822f` + write-response content `81d5717f` (branch merged); MCP share-schema fixes `752a6bc9`/`88f7e2bf`; coverage gate 99/96% enforced.
- **Gate vs merged main: GREEN** — /api/v1 battery (content markdown default on POST/GET/PATCH, search limit+cursor, grants 400), MCP session-auth initialize 200 (unauth 401). Verified by lead directly; image from merged-main tree (Docker cache-hit on identical content — `docker image Created` is NOT a staleness proof when trees match).
- **Subtree sync:** v1 client vendored; fork-local session-auth (auth.ex/http.ex/session_plug) + v1 paths coexist in `mcp/lib/docmost_mcp/client/req.ex`.
- **Infra notes:** e2e creds in `staging/.e2e-session.env` (E2E_SESSION_JWT var name; admin password in file went stale 09-10 — DB reset to re-mint); `staging/.e2e-app-secret` persists APP_SECRET across boots; correct up cmd = 3 compose files + `-p docmost-e2e` + APP_SECRET env (see state-file addendum). Staging checkout left on `develop`.
- **Remaining (owner calls, NOT authorized yet):** fork `develop`→`main` release; docmost-mcp `develop`→`main`; Phase D cluster deploy (docmost.noizu.com, `terraform/kubernetes/platform/content/`).
