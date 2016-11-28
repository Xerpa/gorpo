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

  @typep state_t :: [services: [Gorpo.Service.t], consul: Gorpo.Consul.t, supervisor: pid]

  @doc """
  starts this process. you must provide a valid consul structure in
  the first argument and an optional list of services. Notice that
  this process gets started by the `Gorpo` application which means you
  shouldn't need to manage it directly.
  """
  @spec start_link(Gorpo.Consul.t, [Gorpo.Service.t]) :: {:ok, pid}
  def start_link(consul, services \\ []) do
    GenServer.start_link(__MODULE__, [services: services, consul: consul], name: __MODULE__)
  end

  @doc false
  @spec init(state_t) :: {:ok, state_t}
  def init(state) do
    consul     = Keyword.fetch!(state, :consul)
    {:ok, pid} = state
    |> Keyword.fetch!(:services)
    |> Enum.map(& svc_spec(consul, &1))
    |> Supervisor.start_link(strategy: :one_for_one)

    {:ok, Keyword.put(state, :supervisor, pid)}
  end

  @doc """
  register a service. it uses the `Gorpo.Service.id` to avoid
  registering de process twice. nevertheless, it is ok to invoke this
  function multiple times -- only one process will get registered.

  Each service starts a `Gorpo.Announce.Unit` process. You may use
  the `whereis` to find its pid later.

      iex> service = %Gorpo.Service{id: "foo", name: "bar"}
      iex> :ok = Gorpo.Announce.register(service)
      iex> Gorpo.Announce.register(service)
      :ok
  """
  @spec register(Gorpo.Service.t) :: :ok | {:error, term}
  def register(service) do
    GenServer.call(__MODULE__, {:register, service})
  end

  @doc """
  unregister a service. differently from register it is an error to
  try to unregister a service that doesn't exist.

      iex> service = %Gorpo.Service{id: "foo", name: "bar"}
      iex> :ok = Gorpo.Announce.register(service)
      iex> :ok = Gorpo.Announce.unregister(service)
      iex> Gorpo.Announce.unregister(service)
      {:error, :not_found}
  """
  @spec unregister(Gorpo.Service.t) :: :ok | {:error, term}
  def unregister(service) do
    GenServer.call(__MODULE__, {:unregister, service})
  end

  @doc """
  returns the pid of the `Gorpo.Announce.Unit` process of a given
  service. Returns either the pid of the process or `:unknown`.
  """
  @spec whereis(Gorpo.Service.t) :: pid | :unknown
  def whereis(service) do
    GenServer.call(__MODULE__, {:whereis, service})
  end

  @doc false
  @spec terminate(term, state_t) :: :ok
  def terminate(reason, state) do
    sup = Keyword.fetch!(state, :supervisor)
    Supervisor.stop(sup, reason)
  end

  @doc false
  @spec handle_call(
    {:register | :unregister, Gorpo.Service.t},
    GenServer.from,
    state_t
  ) :: {:reply, :ok | {:error, term}, state_t}
  def handle_call(request, _from, state) do
    case request do
      :killall               -> do_killall(state)
      {:whereis, service}    -> do_whereis(service, state)
      {:register, service}   -> do_register(service, state)
      {:unregister, service} -> do_unregister(service, state)
    end
  end

  defp do_register(service, state) do
    sup    = Keyword.fetch!(state, :supervisor)
    consul = Keyword.fetch!(state, :consul)
    case Supervisor.start_child(sup, svc_spec(consul, service)) do
      {:error, {:already_started, _pid}} -> {:reply, :ok, state}
      {:ok, _pid}                        -> {:reply, :ok, state}
      error                              -> {:reply, error, state}
    end
  end

  defp do_unregister(service, state) do
    sup   = Keyword.fetch!(state, :supervisor)
    svcid = Gorpo.Service.id(service)
    reply = with (:ok <- Supervisor.terminate_child(sup, svcid)) do
              Supervisor.delete_child(sup, svcid)
            end
    {:reply, reply, state}
  end

  defp do_killall(state) do
    sup = Keyword.fetch!(state, :supervisor)
    :ok = Supervisor.which_children(sup)
    |> Enum.each(fn {id, _, _, _} ->
      with (:ok <- Supervisor.terminate_child(sup, id)) do
        Supervisor.delete_child(sup, id)
      end
    end)
    {:reply, :ok, state}
  end

  defp do_whereis(service, state) do
    sup   = Keyword.fetch!(state, :supervisor)
    svcid = Gorpo.Service.id(service)
    Supervisor.which_children(sup)
    |> Enum.filter_map(fn {id, pid, type, _} ->
      id == svcid and type == :worker and is_pid(pid)
    end, fn {_, pid, _, _} ->
      pid
    end)
    |> case do
         [pid]      -> {:reply, pid, state}
         _otherwise -> {:reply, :unknown, state}
       end
  end

  defp svc_spec(consul, service) do
    svcid = Gorpo.Service.id(service)
    Supervisor.Spec.worker(Gorpo.Announce.Unit, [[consul: consul, service: service]],
      id: svcid, restart: :transient, shutdown: 5_000)
  end

end
