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
defmodule Gorpo.Consul do
  @moduledoc """
  consul API interface.
  """

  defstruct [:endpoint, :token, :driver]

  @type url_t :: String.t

  @type method_t :: :get | :put

  @type options_t :: keyword

  @type headers_t :: list

  @type payload_t :: binary | nil

  @type reply_t :: {:error, {:http, [payload: term, headers: keyword, status: integer]}}
                   | {:error, {:driver, any}}
                   | {:ok, [payload: term, headers: keyword, status: integer]}

  @type t :: %__MODULE__{endpoint: String.t,
                         token: String.t | nil,
                         driver: (method_t, url_t, headers_t, payload_t, options_t -> reply_t)}

  @doc """
  search for services.

  * `filters`: restrict the search result. it is a keyword list with any
    combination of the following:

       + `dc `: only services on this datacenter;

       + `tag `: only services with the specified tag;

       + `near`: sort output by proximity to this agent;

       + `status`: only services that have this state;

  """
  @spec services(t,
    String.t,
    [dc: String.t, tag: String.t, near: boolean, status: :passing]
  ) :: reply_t
  def services(cfg, svcname, filters \\ []) do
    path   = "/v1/health/service/#{svcname}"
    params = Enum.reduce(filters, [], fn {k, v}, acc ->
      case {k, v} do
        {:near, true}                   -> [{:near, :_agent} | acc]
        {:near, false}                  -> acc
        {:status, :passing}             -> [{:passing, nil}]
        {:tag, tag} when is_binary(tag) -> [{:tag, tag} | acc]
        {:dc, dc} when is_binary(dc)    -> [{k, v} | acc]
      end
    end)

    reply = driver_req(cfg, :get, path, [{"accept", "application/json"}], nil, [params: params])
    |> replyok_when(& &1[:status] == 200)
    case reply do
      {:ok, reply} ->
        services = reply[:payload]
        |> Poison.decode!
        |> Enum.map(& load_service(svcname, &1))
        {:ok, services}
      reply       -> reply
    end
  end

  @doc """
  register/update a service
  """
  @spec service_register(t, Gorpo.Service.t) :: reply_t
  def service_register(cfg, service) do
    path = "/v1/agent/service/register"
    json = Poison.encode!(service)
    driver_req(cfg, :put, path, json_headers, json, [])
    |> replyok_when(& &1[:status] == 200)
  end

  @doc """
  unregister a service
  """
  @spec service_deregister(t, String.t) :: reply_t
  def service_deregister(cfg, svcid) do
    path = "/v1/agent/service/deregister/#{svcid}"
    driver_req(cfg, :post, path, json_headers, nil, [])
    |> replyok_when(& &1[:status] == 200)
  end

  @doc """
  update health check status for a given service.
  """
  @spec check_update(t, Gorpo.Service.t, Gorpo.Status.t) :: reply_t | {:error, :enocheck}
  def check_update(cfg, service, status) do
    check_id = Gorpo.Service.check_id(service)
    if check_id do
      json = Poison.encode!(status)
      path = "/v1/agent/check/update/#{check_id}"
      driver_req(cfg, :put, path, json_headers, json, [])
      |> replyok_when(& &1[:status] == 200)
    else
      {:error, :enocheck}
    end
  end

  defp json_headers, do: [{"content-type", "application/json"},
                          {"accept", "application/json"}]

  defp driver_req(cfg, method, path, headers, nil, options), do: driver_req(cfg, method, path, headers, "", options)
  defp driver_req(cfg, method, path, headers, payload, options) do
    url  = Enum.join([String.trim_trailing(cfg.endpoint, "/"),
                      String.trim_leading(path, "/")], "/")
    opts = if cfg.token,
             do: Keyword.update(options, :params, [token: cfg.token], & Keyword.put_new(&1, :token, cfg.token)),
             else: options
    cfg.driver.(method, url, headers, payload, opts)
  end

  defp replyok_when(reply, predicate) do
    case reply do
      {:ok, reply} ->
        if predicate.(reply),
          do: {:ok, reply},
          else: {:error, reply}
      error        -> error
    end
  end

  defp load_service(name, data) do
    service = Gorpo.Service.load(name, Map.fetch!(data, "Service"))
    data
    |> Map.fetch!("Checks")
    |> Enum.filter(& Map.get(&1, "CheckID") == Gorpo.Service.check_id(service))
    |> Enum.map(&Gorpo.Status.load/1)
    |> case do
         []       -> {service, nil}
         [status] -> {service, status}
       end
  end

end
