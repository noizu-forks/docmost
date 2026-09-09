defmodule DocmostMCP.ClientBehaviour do
  @moduledoc """
  Boundary used by MCP tools/VFS and replaced by a fake in tests.

  Mirrors the docmost community API v1 contract (see §1 of the community-api-v1
  spec): resource-oriented REST under `/api/v1`, `{data, meta}` list envelopes,
  `{error: {code, message, statusCode}}` errors, PUT share upsert, and
  grant-id page access operations.
  """

  @type result :: {:ok, map() | [map()]} | {:error, DocmostMCP.Error.t()}

  # List callbacks return the raw `{data: [...], meta: {nextCursor}}` envelope;
  # callers page with `DocmostMCP.Normalize.next_cursor/1`.
  @callback list_spaces(String.t() | nil) :: result()
  @callback get_space(String.t()) :: result()
  @callback create_space(map()) :: result()
  @callback list_pages(String.t(), String.t() | nil) :: result()
  @callback list_child_pages(String.t(), String.t() | nil) :: result()
  @callback get_page(String.t()) :: result()
  # `attrs` carries `:spaceId` (routed to the path) and optionally `:content`
  # (`format` defaults to markdown server-side and is never sent).
  @callback create_page(map()) :: result()
  # Meta attrs (`:title`, `:parentId`/`:parentPageId`) go out as
  # `PATCH /v1/pages/:id`; when `attrs` has `:content` (+`:operation`) it goes
  # out as `PUT /v1/pages/:id/content`. Returns the updated page.
  @callback update_page(String.t(), map()) :: result()
  # DELETE /v1/pages/:id — idempotent (204 and 404 both resolve to `:ok`).
  @callback delete_page(String.t()) :: :ok | {:error, DocmostMCP.Error.t()}

  # Share is a single upsert: `%{shared: boolean, includeSubPages?,
  # searchIndexing?}` — `shared: false` deletes the share server-side.
  @callback get_share(String.t()) :: result()
  @callback update_share(String.t(), map()) :: result()

  # Access summary: `{restriction: "none"|"direct"|"inherited", canAccess,
  # canEdit, grants: {data: [grant], meta}}` where grant is
  # `{id, type, principalId, role}`.
  @callback get_access(String.t(), String.t() | nil) :: result()
  @callback set_restriction(String.t(), boolean()) :: result()
  # Batch grant create, max 25 entries of `%{type:, principalId:, role:}`.
  @callback add_grants(String.t(), [map()]) :: result()
  @callback update_grant(String.t(), String.t(), String.t()) :: result()
  # DELETE /v1/pages/:id/access/grants/:grantId — idempotent.
  @callback remove_grant(String.t(), String.t()) :: result()
end
