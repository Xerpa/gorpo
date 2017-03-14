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
defmodule Gorpo do
  @moduledoc """
  An OTP application that announce services on consul. After a
  successful start `Gorpo.Announce` process will be
  running. Unconfigured, it assumes consul is running on localhost:8500
  requiring no ACL and no services are announced.

  Optionally you may provide services that gets announce when this
  application starts. For instance:

      iex> # you may need to restart the application after this
      iex> Application.put_env(:gorpo, :announce, [services: [[id: "foo", name: "bar", check: [ttl: "1s"]]]])
      :ok

  This will announce a service `"bar"` with a health check with a
  `TTL` of `1s`. You may pass additional information [like `tags`] as
  long as they exist in the `Gorpo.Service` [or `Gorpo.Check`]
  struct. Refer to those modules for more information.

  You continue being able to register/unregister a service
  dynamically. Notice that services configured in the application are
  nothing special: you may unregister them like other services you may
  have registered afterwords.
  """
  use Application
  require Logger

  @doc """
  Starts the `Gorpo` application. `Application.put_env(:gorpo, ...)`
  may be used to configure where to find the consul agent and services
  that get announce right from the start. The following keys are
  available:

  * consul: `[endpoint: URL, token: STRING]`

  * announce: `[services: [SERVICE_SPEC]]`;

  `SPEC_SPEC` is a keyword list of keys found in `Gorpo.Service`. A
  valid example:

      [id: "foo",
       name: "bar",
       tags: ["foo", "bar"],
       port: 9000,
       check: CHECK_SPEC,
       address: "127.0.0.1"]

  `CHECK_SPEC` is a keyword list of keys found in `Gorpo.Check`.

      [check: [ttl: "1s"]]
  """
  @spec start(any, any) :: {:ok, pid}
  def start(_type, _args) do
    :ok = inets_start()
    consul   = new_consul()
    services = read_services(announce_cfg())
    announce = Supervisor.Spec.worker(Gorpo.Announce, [consul, services], restart: :permanent)
    Supervisor.start_link([announce], strategy: :one_for_one)
  end

  defp inets_start do
    case :inets.start(:permanent) do
      :ok -> :ok
      {:error, {:already_started, :inets}} -> :ok
    end
  end

  @doc """
  uses the Application.get_env(:gorpo, :consul) to configure and
  return Gorpo.Consul module.
  """
  @spec new_consul() :: Gorpo.Consul.t
  def new_consul do
    read_consul(consul_cfg())
  end

  defp read_consul(config) do
    driver = Gorpo.Drivers.HTTPC.new
    config = Keyword.update(config, :driver, driver, &Gorpo.Drivers.HTTPC.new/1)
    struct(Gorpo.Consul, config)
  end

  defp read_services(config) do
    config
    |> Keyword.fetch!(:services)
    |> Enum.map(&read_service/1)
  end

  defp read_service(service) do
    service = Keyword.update(service, :check, nil, & struct(Gorpo.Check, &1))
    struct(Gorpo.Service, service)
  end

  defp announce_cfg do
    default = [services: []]
    app_cfg = Application.get_env(:gorpo, :announce, [])
    Keyword.merge(default, app_cfg)
  end

  defp consul_cfg do
    default = [endpoint: "http://localhost:8500"]
    app_cfg = Application.get_env(:gorpo, :consul, [])
    Keyword.merge(default, app_cfg)
  end
end
