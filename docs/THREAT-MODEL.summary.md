# Threat Model — summary

Docmost is a multi-tenant collaborative wiki exposed to the internet. Crown
jewels: page content (incl. restricted pages), credentials/sessions, attachment
blobs, and the workspace isolation boundary. Trust boundaries: Internet↔edge,
edge↔app, app↔data stores (Postgres/Redis/blob), app↔third parties (mail, S3/
Azure, Stripe, AI, SSO, SCIM, SIEM), tenant isolation (`workspace_id`), and the
fork's MCP edge→service→Docmost path.

**Surface:** REST `/api/*`, WebSocket/collaboration, file upload/download,
public share + public space pages, auth/SSO callbacks, OAuth2 endpoints, SCIM,
Stripe webhook, health/version.

**Register (15 entries, IDs stable):**
- T-001 High — session JWT signed with single `APP_SECRET` (compose default
  `REPLACE_WITH_LONG_SECRET`) → mitigated-by-config.
- T-002 Mitigated — global workspace guard + strategy workspace/disabled-user checks.
- T-003 Mitigated — only access/api_key/oauth_access token types reach the API.
- T-004 Partial — attachments served inline; `.svg` inline (XSS surface).
- T-005 Partial — named throttlers (auth/oauth/ai/siem) only.
- T-006 Mitigated — iframe embed off by default; OAuth consent force-denied.
- T-007 Open/verify — Stripe webhook signature handling lives in enterprise `ee`.
- T-008 Mitigated-by-default — MCP acts as user; writes gated by `DOCMOST_MCP_WRITES`.
- T-009 Mitigated — MCP static key only opt-in; no fallback from invalid session.
- T-010 Partial — AI egress sends page content to third parties (feature-gated).
- T-011 Mitigated-by-config — store/DB secrets via env, `.env*` gitignored.
- T-012 Partial — audit/SIEM feature-gated.
- T-013 Partial — upload size limit only; no global rate limit.
- T-014 Partial — lockfile + patches, but compose defaults to floating `latest`.
- T-015 Mitigated — bcrypt password hashes; AES-256-GCM helper from `APP_SECRET`.

**Coverage:** 2 mitigated-by-config · 4 mitigated · 7 partial · 1 open/verify ·
opt-in write posture. No Critical open in the AGPL code present.

**Residual risk:** single shared `APP_SECRET` (sessions + encryption key + MCP);
enterprise-only controls (billing/Stripe, SCIM, SIEM, API-key/OAuth validation)
not asserted here; SVG inline XSS accepted; MCP read-only default accepted.

Full detail: [THREAT-MODEL.md](THREAT-MODEL.md)
