import React from "react";
import {
  ActionIcon,
  Anchor,
  Code,
  Divider,
  Group,
  List,
  Stack,
  Text,
  Title,
  Tooltip,
} from "@mantine/core";
import { useTranslation } from "react-i18next";
import { Link } from "react-router-dom";
import SettingsTitle from "@/components/settings/settings-title.tsx";
import { CopyButton } from "@/components/common/copy-button.tsx";
import { DocumentTitle } from "@/components/ui/document-title.tsx";
import useUserRole from "@/hooks/use-user-role.tsx";
import { getAppUrl } from "@/lib/config.ts";
import { IconCheck, IconCopy } from "@tabler/icons-react";

const DOCMOST_TOOLS = [
  "docmost_spaces_list",
  "docmost_pages_list",
  "docmost_page_get",
  "docmost_page_create",
  "docmost_page_update",
  "docmost_page_delete",
  "docmost_page_share",
];

const VFS_TOOLS = [
  "vfs_stat",
  "vfs_list",
  "vfs_read",
  "vfs_write",
  "vfs_create",
  "vfs_remove",
  "vfs_search",
  "vfs_xattr",
];

function CommandWithCopy({ command }: { command: string }) {
  const { t } = useTranslation();
  return (
    <Group gap="xs" align="flex-start" wrap="nowrap" mt={4}>
      <Code block style={{ flex: 1 }}>
        {command}
      </Code>
      <CopyButton value={command} timeout={2000}>
        {({ copied, copy }) => (
          <Tooltip
            label={copied ? t("Copied") : t("Copy")}
            withArrow
            position="right"
          >
            <ActionIcon
              color={copied ? "teal" : "gray"}
              variant="subtle"
              onClick={copy}
            >
              {copied ? <IconCheck size={16} /> : <IconCopy size={16} />}
            </ActionIcon>
          </Tooltip>
        )}
      </CopyButton>
    </Group>
  );
}

export default function McpVfsSettings() {
  const { t } = useTranslation();
  const { isAdmin } = useUserRole();

  if (!isAdmin) {
    return null;
  }

  const mcpUrl = `${getAppUrl()}/mcp`;

  return (
    <>
      <DocumentTitle title={t("MCP Service & VFS")} />
      <SettingsTitle title={t("MCP Service & VFS")} />

      <Stack gap="lg">
        <Text size="sm" c="dimmed">
          {t(
            "The MCP service is the Noizu docmost-mcp Elixir sidecar, served at /mcp over streamable HTTP.",
          )}{" "}
          {t(
            "Requests are authenticated with session identity: the service verifies the Docmost session JWT and performs API calls as the signed-in user. CLI and stdio clients can authenticate with a Docmost API key instead (operator opt-in).",
          )}
        </Text>

        <Divider />

        <div>
          <Title order={3} size="h4" mb="xs">
            {t("Service endpoint")}
          </Title>
          <CommandWithCopy command={mcpUrl} />
          <Text size="sm" c="dimmed" mt="xs">
            {t(
              "CLI and stdio MCP clients authenticate with a Docmost API key.",
            )}{" "}
            <Anchor component={Link} to="/settings/api-keys" size="sm">
              {t("Manage API keys")}
            </Anchor>
          </Text>
        </div>

        <Divider />

        <div>
          <Title order={3} size="h4" mb="xs">
            {t("Available tools")}
          </Title>
          <Text size="sm" fw={500} mb={4}>
            {t("Docmost tools")}
          </Text>
          <List size="sm" spacing={2} withPadding>
            {DOCMOST_TOOLS.map((tool) => (
              <List.Item key={tool}>
                <Code>{tool}</Code>
              </List.Item>
            ))}
          </List>
          <Text size="sm" fw={500} mb={4} mt="sm">
            {t("VFS tools")}
          </Text>
          <List size="sm" spacing={2} withPadding>
            {VFS_TOOLS.map((tool) => (
              <List.Item key={tool}>
                <Code>{tool}</Code>
              </List.Item>
            ))}
          </List>
        </div>

        <Divider />

        <div>
          <Title order={3} size="h4" mb="xs">
            {t("VFS mount")}
          </Title>
          <Stack gap="xs" mb="md">
            <Text size="sm" c="dimmed">
              {t(
                "The VFS projects the workspace as a filesystem: each space becomes a directory and each page a Markdown file, with page nesting derived from the page's parent frontmatter.",
              )}
            </Text>
            <Text size="sm" c="dimmed">
              {t(
                "Each page has a sibling .meta file — a one-way YAML command file for share and access state. Full .meta read output includes protected fields and is intentionally rejected when written back verbatim; write a minimal YAML command with only the keys you want to change.",
              )}
            </Text>
            <Text size="sm" c="dimmed">
              {t(
                "All mutations (page create, update, delete, share and VFS writes) are refused unless the service runs with DOCMOST_MCP_WRITES=1. The default posture is read-only.",
              )}
            </Text>
          </Stack>

          <List size="sm" type="ordered" spacing="md">
            <List.Item>
              {t("Clone the client repo:")}
              <CommandWithCopy
                command={
                  "git clone https://github.com/noizu-labs/docmost-mcp\ncd docmost-mcp"
                }
              />
            </List.Item>
            <List.Item>
              {t("Create a Docmost API key for the MCP client under")}{" "}
              <Anchor component={Link} to="/settings/api-keys" size="sm">
                {t("API management")}
              </Anchor>
              .
            </List.Item>
            <List.Item>
              {t("Configure the environment (defaults to read-only):")}
              <CommandWithCopy
                command={
                  'export DOCMOST_API_URL="https://docmost.example.com"\nexport DOCMOST_API_KEY="<your-api-key>"\n# opt in to all mutations (off by default):\nexport DOCMOST_MCP_WRITES=1'
                }
              />
            </List.Item>
            <List.Item>
              {t("Run the server; it speaks MCP over stdio:")}
              <CommandWithCopy command={"mix deps.get\nmix run --no-halt"} />
            </List.Item>
            <List.Item>
              <Stack gap={4}>
                <Text size="sm">
                  {t(
                    "Optionally expose the VFS as a local FUSE mount. Start the server with a mount token (the listener binds to 127.0.0.1 only):",
                  )}
                </Text>
                <CommandWithCopy
                  command={
                    "DOCMOST_MCP_MOUNT_TOKEN=$(openssl rand -hex 32) DOCMOST_MCP_MOUNT_PORT=4700 mix run --no-halt"
                  }
                />
                <Text size="sm">{t("Then mount it read-only:")}</Text>
                <CommandWithCopy
                  command={
                    'mcp-mount --transport vfs-ws --url ws://127.0.0.1:4700/vfs --token "$DOCMOST_MCP_MOUNT_TOKEN" ~/wiki'
                  }
                />
                <Text size="sm">
                  {t("Or with writes (still gated by DOCMOST_MCP_WRITES):")}
                </Text>
                <CommandWithCopy
                  command={
                    'mcp-mount --transport vfs-ws --url ws://127.0.0.1:4700/vfs --token "$DOCMOST_MCP_MOUNT_TOKEN" --write ~/wiki'
                  }
                />
              </Stack>
            </List.Item>
          </List>
          <Text size="sm" c="dimmed" mt="xs">
            {t(
              "The write gate can be flipped at runtime without a restart by writing true or false to /etc/dev/config/writes (visible in the mount at ~/wiki/etc/dev/config/writes).",
            )}
          </Text>
        </div>

        <Divider />

        <div>
          <Title order={3} size="h4" mb="xs">
            {t("Selfhost deployment")}
          </Title>
          <Text size="sm" c="dimmed" mb="xs">
            {t(
              "To enable the sidecar on a selfhosted deployment of this fork, run:",
            )}
          </Text>
          <CommandWithCopy
            command={
              "docker compose -f docker-compose.yml -f docker-compose.mcp.yml up -d"
            }
          />
          <Text size="sm" c="dimmed" mt="xs">
            {t(
              "This starts the mcp service (streamable HTTP on port 4000) and a Caddy edge proxy that routes /mcp* to it. Session-identity auth shares APP_SECRET with the Docmost app. Our Kubernetes deployment of the sidecar is tracked separately.",
            )}
          </Text>
        </div>
      </Stack>
    </>
  );
}
