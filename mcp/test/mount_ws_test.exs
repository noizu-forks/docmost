defmodule DocmostMCP.MountWSTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Boots the mount stack (VFSPubSub + Bandit-hosted VFSWS) against the real
  DocmostMCP.Server (VFS.Controlled -> VFS.Backend over TestClient) and drives
  the wire protocol with a Mint.WebSocket client.
  """

  @token "test-mount-token"
  @event_timeout 2_000

  alias __MODULE__.WSClient

  setup do
    {:ok, _} = DocmostMCP.TestClient.start()
    DocmostMCP.VersionStore.reset()

    original = Application.get_env(:docmost_mcp, :writes)
    on_exit(fn -> Application.put_env(:docmost_mcp, :writes, original) end)
    Application.put_env(:docmost_mcp, :writes, true)

    port = free_port()

    start_supervised!({Noizu.MCP.Server.VFSPubSub, []})

    start_supervised!(
      {Bandit,
       plug:
         {Noizu.MCP.Transport.VFSWS,
          server: DocmostMCP.Server,
          auth: [
            verifier: {Noizu.MCP.Auth.ApiKeyVerifier, keys: [{@token, %{"sub" => "test-mount"}}]}
          ]},
       scheme: :http,
       port: port,
       ip: {127, 0, 0, 1}}
    )

    %{port: port}
  end

  # ── upgrade auth ────────────────────────────────────────────────────────────

  test "missing bearer token is rejected 401 before any socket exists", %{port: port} do
    assert {:error, :not_upgraded, 401} = WSClient.connect(port, "/vfs", [])
  end

  test "wrong bearer token is rejected 401", %{port: port} do
    assert {:error, :not_upgraded, 401} =
             WSClient.connect(port, "/vfs", [{"authorization", "Bearer nope"}])
  end

  test "operations before vfs/auth draw -32001 and close", %{port: port} do
    {:ok, client} =
      WSClient.connect(port, "/vfs", [{"authorization", "Bearer " <> @token}])

    client = WSClient.send_text(client, %{"v" => 2, "id" => 1, "method" => "vfs/ping"})

    assert {:ok, client, frame} = WSClient.recv(client)
    assert frame["error"]["code"] == -32_001

    # mint_web_socket surfaces the server close as {:close, code, reason}.
    assert {:closed, _client, {:close, 1008, _reason}} = WSClient.recv(client)
  end

  test "vfs/auth with the wrong frame token draws -32001", %{port: port} do
    {:ok, client} =
      WSClient.connect(port, "/vfs", [{"authorization", "Bearer " <> @token}])

    client =
      WSClient.send_text(client, %{
        "v" => 2,
        "id" => 1,
        "method" => "vfs/auth",
        "params" => %{"token" => "wrong"}
      })

    assert {:ok, _client, frame} = WSClient.recv(client)
    assert frame["error"]["code"] == -32_001
  end

  # ── authenticated operations ────────────────────────────────────────────────

  test "vfs/auth + ping round-trips", %{port: port} do
    {:ok, client} = authed(port)
    client = WSClient.send_text(client, %{"v" => 2, "id" => 2, "method" => "vfs/ping"})

    assert {:ok, _client, frame} = WSClient.recv(client)
    assert frame["id"] == 2
    assert frame["result"] == %{"pong" => true}
  end

  test "vfs/stat and vfs/read serve TestClient-seeded paths", %{port: port} do
    {:ok, client} = authed(port)

    client =
      WSClient.send_text(client, %{
        "v" => 2,
        "id" => 3,
        "method" => "vfs/stat",
        "params" => %{"path" => "/engineering/start.md"}
      })

    assert {:ok, _client, frame} = WSClient.recv(client)
    assert %{"type" => "file", "writable" => true, "version" => v} = frame["result"]
    assert is_integer(v)

    client =
      WSClient.send_text(client, %{
        "v" => 2,
        "id" => 4,
        "method" => "vfs/read",
        "params" => %{"path" => "/engineering/start.md"}
      })

    assert {:ok, _client, frame} = WSClient.recv(client)
    assert %{"content" => content, "version" => version} = frame["result"]
    assert content =~ "# Start"
    assert version == v
  end

  test "a write with the gate off is -32040 (:eacces)", %{port: port} do
    Application.put_env(:docmost_mcp, :writes, false)
    {:ok, client} = authed(port)

    client = write_frame(client, 5)

    assert {:ok, _client, frame} = WSClient.recv(client)
    assert frame["error"]["code"] == -32_040
    assert frame["error"]["data"]["errno_atom"] == "eacces"
  end

  test "a gated write succeeds and pushes a vfs/event to a subscribed peer", %{port: port} do
    {:ok, watcher} = authed(port)

    watcher =
      WSClient.send_text(watcher, %{
        "v" => 2,
        "id" => 6,
        "method" => "vfs/subscribe",
        "params" => %{"paths" => ["/engineering"]}
      })

    assert {:ok, watcher, frame} = WSClient.recv(watcher)
    assert frame["result"] == %{"subscribed" => true}

    {:ok, writer} = authed(port)
    writer = write_frame(writer, 7)
    assert {:ok, _writer, frame} = WSClient.recv(writer)
    assert %{"version" => _} = frame["result"]

    assert {:ok, _watcher, event} = WSClient.recv(watcher, @event_timeout)
    assert event["type"] == "vfs/event"
    assert event["op"] == "write"
    assert event["path"] == "/engineering/start.md"
    assert is_integer(event["version"])
  end

  defp authed(port) do
    {:ok, client} = WSClient.connect(port, "/vfs", [{"authorization", "Bearer " <> @token}])

    client =
      WSClient.send_text(client, %{
        "v" => 2,
        "id" => 1,
        "method" => "vfs/auth",
        "params" => %{"token" => @token}
      })

    assert {:ok, client, frame} = WSClient.recv(client)
    assert frame["result"]["authenticated"] == true
    {:ok, client}
  end

  defp write_frame(client, id) do
    WSClient.send_text(client, %{
      "v" => 2,
      "id" => id,
      "method" => "vfs/write",
      "params" => %{"path" => "/engineering/start.md", "data" => "# Mounted\n"}
    })
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # ── Mint.WebSocket test client (adapted from noizu_mcp's VFSWS tests) ──────

  defmodule WSClient do
    defstruct [:conn, :ref, :ws, :queue, :close]

    def connect(port, path, headers) do
      with {:ok, conn} <-
             Mint.HTTP.connect(:http, "127.0.0.1", port, protocols: [:http1], mode: :passive),
           {:ok, conn, ref} <- Mint.WebSocket.upgrade(:ws, conn, path, headers),
           {:ok, conn, responses} <- Mint.HTTP.recv(conn, 0, 2000) do
        with {:ok, 101, resp_headers} <- upgrade_response(responses, ref),
             {:ok, conn, ws} <- Mint.WebSocket.new(conn, ref, 101, resp_headers) do
          {:ok, %__MODULE__{conn: conn, ref: ref, ws: ws, queue: []}}
        else
          {:ok, status, _headers} -> {:error, :not_upgraded, status}
          error -> error
        end
      else
        {:error, conn, reason} -> {:error, conn, reason}
        error -> error
      end
    end

    defp upgrade_response(responses, ref) do
      status =
        Enum.find_value(responses, fn
          {:status, ^ref, status} -> status
          _ -> nil
        end)

      headers =
        Enum.find_value(responses, fn
          {:headers, ^ref, headers} -> headers
          _ -> nil
        end)

      if status && headers, do: {:ok, status, headers}, else: {:error, :incomplete_upgrade}
    end

    def send_text(%__MODULE__{} = client, term) do
      {:ok, ws, data} = Mint.WebSocket.encode(client.ws, {:text, Jason.encode!(term)})
      {:ok, conn} = Mint.WebSocket.stream_request_body(client.conn, client.ref, data)
      %{client | ws: ws, conn: conn}
    end

    def recv(client, timeout \\ 2000)

    def recv(%__MODULE__{close: close} = client, _timeout) when close != nil do
      {:closed, client, close}
    end

    def recv(%__MODULE__{queue: [text | rest]} = client, _timeout) do
      {:ok, %{client | queue: rest}, Jason.decode!(text)}
    end

    def recv(%__MODULE__{} = client, timeout) do
      case Mint.WebSocket.recv(client.conn, 0, timeout) do
        {:ok, conn, responses} ->
          datas = for {:data, _, data} <- responses, do: data
          decode(client, conn, IO.iodata_to_binary(datas), timeout)

        {:error, conn, %Mint.TransportError{reason: :closed}, _} ->
          {:closed, %{client | conn: conn}, :closed}

        {:error, conn, reason, _} ->
          {:error, %{client | conn: conn}, reason}
      end
    end

    defp decode(client, conn, data, timeout) do
      case Mint.WebSocket.decode(client.ws, data) do
        {:ok, ws, frames} ->
          client = maybe_pong(%{client | ws: ws, conn: conn}, frames)

          {texts, rest} = Enum.split_with(frames, &match?({:text, _}, &1))
          texts = Enum.map(texts, fn {:text, t} -> t end)

          close =
            Enum.find(rest, &match?({:close, _, _}, &1)) ||
              Enum.find(rest, &match?({:close, _}, &1))

          cond do
            texts != [] ->
              [text | queued] = texts
              {:ok, %{client | queue: queued, close: close || client.close}, Jason.decode!(text)}

            close != nil ->
              {:closed, client, close}

            true ->
              recv(client, timeout)
          end

        {:error, ws, reason} ->
          {:error, %{client | ws: ws, conn: conn}, reason}
      end
    end

    defp maybe_pong(client, frames) do
      Enum.reduce(frames, client, fn
        {:ping, data}, acc ->
          {:ok, ws, payload} = Mint.WebSocket.encode(acc.ws, {:pong, data})
          {:ok, conn} = Mint.WebSocket.stream_request_body(acc.conn, acc.ref, payload)
          %{acc | ws: ws, conn: conn}

        _, acc ->
          acc
      end)
    end
  end
end
