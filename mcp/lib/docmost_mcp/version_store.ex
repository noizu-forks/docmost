defmodule DocmostMCP.VersionStore do
  @moduledoc "Stable monotonic VFS versions for remote representations."
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def version(path, fingerprint), do: GenServer.call(__MODULE__, {:version, path, fingerprint})
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:version, path, fingerprint}, _from, state) do
    case state[path] do
      {^fingerprint, version} -> {:reply, version, state}
      {_old, version} -> {:reply, version + 1, Map.put(state, path, {fingerprint, version + 1})}
      nil -> {:reply, 1, Map.put(state, path, {fingerprint, 1})}
    end
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}
end
