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
defmodule Gorpo.Announce do
  @moduledoc """
  register one or more services on consul and periodically update its
  health status. Normally, you should start :gorpo otp application and
  declare the services in the config file. Refer to `Gorpo` module for
  more information about this. If you ever need to register a service
  dynamically:

      iex> service = %Gorpo.Service{id: "foobar", name: "foobar", check: %Gorpo.Check{}}
      iex> Gorpo.Announce.register(service)
      :ok

  To unregister a service:

      iex> service = %Gorpo.Service{id: "foobar", name: "foobar", check: %Gorpo.Check{}}
      iex> :ok = Gorpo.Announce.register(service)
      iex> Gorpo.Announce.unregister(service)
      :ok

  Lastly, you may ask for the `Gorpo.Announce.Unit` pid [and then check its status]:

      iex> service = %Gorpo.Service{id: "foobar", name: "foobar"}
      iex> :ok = Gorpo.Announce.register(service)
      iex> Gorpo.Announce.whereis(service)
      ...> |> Gorpo.Announce.Unit.stat
      ...> |> Keyword.keys
      [:service, :heartbeat]
  """

  use GenServer

  require Logger

  defstruct [:services, :consul, :supervisor]

  @typep state :: %__MODULE__{
    services: [Gorpo.Service.t],
    consul: Gorpo.Consul.t,
    supervisor: pid
  }

  @spec start_link(Gorpo.Consul.t, [Gorpo.Service.t]) :: GenServer.on_start
  @doc """
  Starts this process.

  You must provide a valid Consul structure in the first argument and an
  optional list of services. Notice that this process gets started by the
  `Gorpo` application which means you shouldn't need to manage it directly.
  """
  def start_link(consul, services \\ []) do
    GenServer.start_link(__MODULE__, [services: services, consul: consul], name: __MODULE__)
  end

  @spec init(Keyword.t) :: {:ok, state}
  @doc false
  def init(params) do
    consul = Keyword.fetch!(params, :consul)
    services = Keyword.fetch!(params, :services)

    {:ok, supervisor} =
      services
      |> Enum.map(& child_service(consul, &1))
      |> Supervisor.start_link(strategy: :one_for_one)

    state = %__MODULE__{
      consul: consul,
      services: services,
      supervisor: supervisor
    }

    {:ok, state}
  end

  @spec register(Gorpo.Service.t) :: :ok | {:error, term}
  @doc """
  Registers a service.

  It uses the `Gorpo.Service.id` to avoid registering the process twice.
  Nevertheless, it is ok to invoke this function multiple times - only one
  process will get registered.

  Each service starts a `Gorpo.Announce.Unit` process. You may use the `whereis`
  to find its pid later.

      iex> service = %Gorpo.Service{id: "foo", name: "bar"}
      iex> :ok = Gorpo.Announce.register(service)
      iex> Gorpo.Announce.register(service)
      :ok
  """
  def register(service) do
    GenServer.call(__MODULE__, {:register, service})
  end

  @spec unregister(Gorpo.Service.t) :: :ok | {:error, term}
  @doc """
  Unregisters a service.

  Differently from register it is an error to try to unregister a service that
  doesn't exist.

      iex> service = %Gorpo.Service{id: "foo", name: "bar"}
      iex> :ok = Gorpo.Announce.register(service)
      iex> :ok = Gorpo.Announce.unregister(service)
      iex> Gorpo.Announce.unregister(service)
      {:error, :not_found}
  """
  def unregister(service) do
    GenServer.call(__MODULE__, {:unregister, service})
  end

  @spec whereis(Gorpo.Service.t) :: pid | :unknown
  @doc """
  Returns the pid of the `Gorpo.Announce.Unit` process of a given service.

  Returns either the pid of the process or `:unknown`.
  """
  def whereis(service) do
    GenServer.call(__MODULE__, {:whereis, service})
  end

  @spec terminate(term, state) :: :ok
  @doc false
  def terminate(reason, state) do
    Supervisor.stop(state.supervisor, reason)
  end

  @spec handle_call(:killall, GenServer.from, state) :: {:reply, :ok, state}
  @doc false
  def handle_call(:killall, _, state) do
    state.supervisor
    |> Supervisor.which_children()
    |> Enum.each(fn {id, _, _, _} ->
      with :ok <- Supervisor.terminate_child(state.supervisor, id) do
        Supervisor.delete_child(state.supervisor, id)
      end
    end)

    {:reply, :ok, state}
  end

  @spec handle_call({:whereis, Gorpo.Service.t}, GenServer.from, state) :: {:reply, pid | :unknown, state}
  def handle_call({:whereis, service}, _, state) do
    service_id = Gorpo.Service.id(service)

    location =
      state.supervisor
      |> Supervisor.which_children()
      |> Enum.find_value(:unknown, fn {id, pid, type, _} ->
        id == service_id
        && type == :worker
        && pid
      end)

    {:reply, location, state}
  end

  @spec handle_call({:register, Gorpo.Service.t}, GenServer.from, state) :: {:reply, :ok | {:error, term}, state}
  def handle_call({:register, service}, _, state) do
    child = child_service(state.consul, service)

    case Supervisor.start_child(state.supervisor, child) do
      {:error, {:already_started, _pid}} ->
        {:reply, :ok, state}
      {:ok, _pid} ->
        {:reply, :ok, state}
      error ->
        {:reply, error, state}
    end
  end

  @spec handle_call({:unregister, Gorpo.Service.t}, GenServer.from, state) :: {:reply, :ok | {:error, :not_found}, state}
  def handle_call({:unregister, service}, _, state) do
    service_id = Gorpo.Service.id(service)

    case Supervisor.terminate_child(state.supervisor, service_id) do
      :ok ->
        Supervisor.delete_child(state.supervisor, service_id)
        {:reply, :ok, state}
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @spec child_service(Gorpo.Consul.t, Gorpo.Service.t) :: Supervisor.Spec.spec
  defp child_service(consul, service) do
    Supervisor.Spec.worker(
      Gorpo.Announce.Unit,
      [[consul: consul, service: service]],
      id: Gorpo.Service.id(service),
      restart: :transient,
      shutdown: 5_000)
  end
end
