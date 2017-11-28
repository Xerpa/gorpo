# Copyright (c) 2016, Diego Vinicius e Souza All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
defmodule Gorpo.Announce.Unit do
  @moduledoc """
  register a service on consul and periodically update its health
  status. Normally, you shouldn't need to use this module
  directly. Use Gorpo.Announce instead. The next example uses a dummy
  driver which does nothing. You should use `Gorpo.Drivers.HTTPC` for
  a real case.

      iex> driver     = Gorpo.Drivers.Echo.success([status: 200])
      iex> consul     = %Gorpo.Consul{endpoint: "http://localhost:8500", driver: driver}
      iex> service    = %Gorpo.Service{id: "foobar", name: "foobar", check: %Gorpo.Check{}}
      iex> {:ok, pid} = Gorpo.Announce.Unit.start_link(service: service, consul: consul)
      iex> Gorpo.Announce.Unit.stat(pid)
      [service: :ok, heartbeat: :ok]

  Notice that a service without a check ignores the heartbeat:

      iex> driver     = Gorpo.Drivers.Echo.success([status: 200])
      iex> consul     = %Gorpo.Consul{endpoint: "http://localhost:8500", driver: driver}
      iex> service    = %Gorpo.Service{id: "foobar", name: "foobar"}
      iex> {:ok, pid} = Gorpo.Announce.Unit.start_link(service: service, consul: consul)
      iex> Gorpo.Announce.Unit.stat(pid)
      [service: :ok, heartbeat: :error]
  """

  use GenServer

  require Logger

  defstruct [:service, :consul, :wait, :tick, :timer, :status]

  @type start_options :: [
    service: Gorpo.Service.t,
    consul: Gorpo.Consul.t
  ]

  @typep state :: %__MODULE__{
    service: Gorpo.Service.t,
    consul: Gorpo.Consul.t,
    wait: pos_integer,
    tick: pos_integer,
    timer: :timer.tref | nil,
    status: map
  }

  @spec stat(pid) :: [service: :ok | :error, heartbeat: :ok | :error]
  @doc """
  Returns a keyword list with the status of the service registration and
  heatbeat.
  """
  def stat(pid),
    do: GenServer.call(pid, :stat)

  @spec start_link(start_options) :: {:ok, pid}
  @doc """
  Starts this process.

  Expects a keyword which describes the service to register and the Consul
  configuration.
  """
  def start_link(state),
    do: GenServer.start_link(__MODULE__, state)

  @doc """
  Will register the service and perform the first health check update
  synchronously. an error registering the service or updating the
  check status will not impede the process initialization.

  Keep in mind that this may take a while as it will wait for both the
  service registration and check update responses, which may take
  arbitrarily long depending on the consul backend in use.
  """
  def init(params) do
    service = params[:service]
    tick = tickof(service)

    state = %__MODULE__{
      service: service,
      consul: params[:consul],
      tick: tick,
      wait: tick,
      status: %{}
    }

    {:noreply, state} = handle_info(:tick, state)

    Logger.info("#{__MODULE__} register #{service.name}.#{service.id}: #{state.status[:service]}")

    {:ok, state}
  end

  @spec terminate(term, state) :: :ok | :error
  @doc """
  Deregister the service on Consul. returns `:ok` on success or `:error`
  otherwise.
  """
  def terminate(_reason, state) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    service = state.service
    {status, _} = Gorpo.Consul.service_deregister(state.consul, service.id)

    Logger.info("#{__MODULE__} deregister #{service.name}.#{service.id}: #{status}")

    status
  end

  @doc false
  def handle_info(:tick, state) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    service = state.service
    status = Map.get(state.status, :service, :error)
    name = "#{service.name}.#{service.id}"

    case process_tick(state) do
      {:ok, state} ->
        unless status == :ok do
          Logger.debug "#{__MODULE__} #{name}: ok"
        end

        timer = Process.send_after(self(), :tick, state.wait)

        state = %{state| timer: timer, wait: state.tick}

        {:noreply, state}
      {:error, reason, state} ->
        Logger.warn "#{__MODULE__} #{name}: #{inspect reason} [backoff: #{state.wait}]"

        timer = Process.send_after(self(), :tick, state.wait)

        state = %{
          state|
            timer: timer,
            wait: min(state.wait * 2, 300_000),
            status: %{}
        }

        {:noreply, state}
    end
  end

  @doc false
  def handle_call(:stat, _, state) do
    reply = [
      service: Map.get(state.status, :service, :error),
      heartbeat: Map.get(state.status, :heartbeat, :error)
    ]

    {:reply, reply, state}
  end

  @spec process_tick(state) :: {:ok, state} | {:error, {:heartbeat | :service, term}, state}
  defp process_tick(state) do
    case Map.fetch(state.status, :service) do
      {:ok, :ok} ->
        do_heartbeat(state)
      :error ->
        with {:ok, state} <- do_service(state) do
          do_heartbeat(state)
        end
    end
  end

  @spec do_service(state) :: {:ok, state} | {:error, {:service, term}, state}
  defp do_service(state) do
    case Gorpo.Consul.service_register(state.consul, state.service) do
      {:ok, _} ->
        {:ok, %{state| status: Map.put(state.status, :service, :ok)}}
      error ->
        {:error, {:service, error}, state}
    end
  end

  @spec do_heartbeat(state) :: {:ok, state} | {:error, {:heartbeat, term}, state}
  defp do_heartbeat(state) do
    if state.service.check do
      status = Gorpo.Status.passing

      case Gorpo.Consul.check_update(state.consul, state.service, status) do
        {:ok, _} ->
          {:ok, %{state| status: Map.put(state.status, :heartbeat, :ok)}}
        error ->
          {:error, {:heartbeat, error}, state}
      end
    else
      {:ok, state}
    end
  end

  @spec tickof(Gorpo.Service.t) :: pos_integer
  defp tickof(service) do
    if service.check do
      ms = case Integer.parse(service.check.ttl) do
        {n, "h"} -> n * 1000 * 60 * 60
        {n, "m"} -> n * 1000 * 60
        {n, "s"} -> n * 1000
        {n, ""}  -> n
      end

      ms
      |> div(5)
      |> max(50)
    else
      5 * 1000 * 60
    end
  end
end
