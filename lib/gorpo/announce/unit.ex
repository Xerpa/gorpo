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

  @type state_t    :: [service: %Gorpo.Service{}, consul: %Gorpo.Consul{}]

  @typep istate_t :: [service: %Gorpo.Service{}, consul: %Gorpo.Consul{}, wait: integer, tick: integer, timer: :timer.tref]

  use GenServer
  require Logger

  @doc """
  returns a keyword list with the status of the service registration
  and heatbeat.
  """
  @spec stat(pid) :: [service: :ok|:error, heartbeat: :ok|:error]
  def stat(pid), do: GenServer.call(pid, :stat)

  @doc """
  starts this process. it expects a keyword list which describes the
  service to register and the consul configuration.
  """
  @spec start_link(state_t) :: {:ok, pid}
  def start_link(state), do: GenServer.start_link(__MODULE__, state)

  @doc """
  will register the service and perform the first health check update
  synchronously. an error registering the service or updating the
  check status will not impede the process initialization.

  keep in mind that this may take a while as it will wait for both the
  service registration and check update responses, which may take
  arbitrarily long depending on the consul backend in use.
  """
  @spec init(state_t) :: {:ok, istate_t}
  def init(state) do
    svc   = state[:service]
    tick  = tickof(svc)
    state = state
    |> Keyword.put(:tick, tick)
    |> Keyword.put(:wait, tick)
    {:noreply, state} = handle_info(:tick, state)
    Logger.info("#{__MODULE__} register #{svc.name}.#{svc.id}: #{state[:service_state]}")
    {:ok, state}
  end

  @doc """
  deregister the service on consul. returns an `:ok` on success or
  `:error` otherwise.
  """
  @spec terminate(term, istate_t) :: :ok | :error
  def terminate(_reason, state) do
    if state[:timer],
      do: Process.cancel_timer(state[:timer])

    service   = state[:service]
    {stat, _} = Gorpo.Consul.service_deregister(state[:consul], service.id)
    Logger.info("#{__MODULE__} deregister #{service.name}.#{service.id}: #{stat}")
    stat
  end

  @doc false
  @spec handle_info(:tick, istate_t) :: {:noreply, istate_t}
  def handle_info(:tick, state) do
    if state[:timer],
      do: Process.cancel_timer(state[:timer])

    service = state[:service]
    svcstat = state[:service_stat]
    svcname = "#{service.name}.#{service.id}"
    case process_tick(state) do
      {:ok, state}          ->
        if :ok != svcstat,
          do: Logger.debug("#{__MODULE__} #{svcname}: ok")
        timer = Process.send_after(self(), :tick, state[:wait])
        {:noreply, st_ok(state) |> Keyword.put(:timer, timer)}
      {:error, reason, state} ->
        reason = inspect(reason)
        Logger.warn "#{__MODULE__} #{svcname}: #{reason} [backoff: #{state[:wait]}]"
        timer = Process.send_after(self(), :tick, state[:wait])
        {:noreply, st_error(state) |> Keyword.put(:timer, timer)}
    end
  end

  def handle_call(:stat, _from, state) do
    reply = [service: Keyword.get(state, :service_stat, :error),
             heartbeat: Keyword.get(state, :heartbeat_stat, :error)]
    {:reply, reply, state}
  end

  defp process_tick(state) do
    case Keyword.fetch(state, :service_stat) do
      {:ok, :ok} -> do_heartbeat(state)
      :error     ->
        with ({:ok, state} <- do_service(state)) do
          do_heartbeat(state)
        end
    end
  end

  defp do_service(state) do
    case Gorpo.Consul.service_register(state[:consul], state[:service]) do
      {:ok, _} -> {:ok, Keyword.put(state, :service_stat, :ok)}
      error    -> {:error, {:service, error}, state}
    end
  end

  defp do_heartbeat(state) do
    if is_nil(state[:service].check) do
      {:ok, state}
    else
      status = Gorpo.Status.passing
      case Gorpo.Consul.check_update(state[:consul], state[:service], status) do
        {:ok, _} -> {:ok, Keyword.put(state, :heartbeat_stat, :ok)}
        error    -> {:error, {:heartbeat, error}, state}
      end
    end
  end

  defp st_ok(state) do
    Keyword.put(state, :wait, state[:tick])
  end

  defp st_error(state) do
    state
    |> Keyword.delete(:service_stat)
    |> Keyword.delete(:heartbeat_stat)
    |> Keyword.put(:wait, min(state[:wait] * 2, 300_000))
  end

  defp tickof(service) do
    if (service.check) do
      case Integer.parse(service.check.ttl) do
        {n, "h"} -> n * 1000 * 60 * 60
        {n, "m"} -> n * 1000 * 60
        {n, "s"} -> n * 1000
        {n, ""}  -> n
      end
      |> div(5)
      |> max(50)
    else
      5 * 1000 * 60
    end
  end

end
