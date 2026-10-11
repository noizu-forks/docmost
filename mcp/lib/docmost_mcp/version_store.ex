defmodule DocmostMCP.VersionStore do
  @moduledoc "Stable monotonic VFS versions for remote representations."
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def version(path, fingerprint), do: GenServer.call(__MODULE__, {:version, path, fingerprint})
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_state), do: {:ok, new_state(System.system_time(:second))}

  @impl true
  def handle_call({:version, path, fingerprint}, _from, state) do
    case state.paths[path] do
      {^fingerprint, version} ->
        {:reply, version, state}

      {_old, version} ->
        {:reply, version + 1, put_version(state, path, fingerprint, version + 1)}

      nil ->
        # Fresh paths start at the boot epoch so every version this process has
        # ever handed out stays below every version the *next* boot hands out —
        # a restart (changed upstream world) forces clients to re-pull.
        {:reply, state.epoch, put_version(state, path, fingerprint, state.epoch)}
    end
  end

  def handle_call(:reset, _from, state) do
    # Bump the epoch past everything issued so far: a reset means "the world
    # changed underneath us", so post-reset versions must exceed pre-reset ones.
    highest =
      state.paths |> Map.values() |> Enum.map(&elem(&1, 1)) |> Enum.max(&>=/2, fn -> 0 end)

    {:reply, :ok, new_state(max(System.system_time(:second), highest + 1))}
  end

  defp new_state(epoch), do: %{epoch: max(1, epoch), paths: %{}}

  defp put_version(state, path, fingerprint, version),
    do: %{state | paths: Map.put(state.paths, path, {fingerprint, version})}
end
