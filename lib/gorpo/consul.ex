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

  @type reply_t :: error_reply_t | ok_reply_t

  @type ok_reply_t :: {:ok, [payload: term, headers: keyword, status: integer]}

  @type error_reply_t :: {:error, {:http, [payload: term, headers: keyword, status: integer]}}
                         | {:error, {:driver, any}}

  @type t :: %__MODULE__{endpoint: String.t,
                         token: String.t | nil,
                         driver: (method_t, url_t, headers_t, payload_t, options_t -> reply_t)}

  @type session_t :: String.t

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
  ) :: {:ok, [Gorpo.Service.t]} | error_reply_t
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

    driver_req(cfg, :get, path, [{"accept", "application/json"}], nil, [params: params])
    |> replyok_when(& &1[:status] == 200)
    |> case do
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
    driver_req(cfg, :put, path, json_headers(), json, [])
    |> replyok_when(& &1[:status] == 200)
  end

  @doc """
  unregister a service
  """
  @spec service_deregister(t, String.t) :: reply_t
  def service_deregister(cfg, svcid) do
    path = "/v1/agent/service/deregister/#{svcid}"
    driver_req(cfg, :post, path, json_headers(), nil, [])
    |> replyok_when(& &1[:status] == 200)
  end

  @doc """
  update health check status for a given service.
  """
  @spec check_update(t, Gorpo.Service.t, Gorpo.Status.t) :: ok_reply_t | {:error, :not_found}
  def check_update(cfg, service, status) do
    check_id = Gorpo.Service.check_id(service)
    if check_id do
      json = Poison.encode!(status)
      path = "/v1/agent/check/update/#{check_id}"
      driver_req(cfg, :put, path, json_headers(), json, [])
      |> replyok_when(& &1[:status] == 200)
    else
      {:error, :not_found}
    end
  end

  @doc """
  acquires a new session using the TTL method.
  """
  @spec session_create(t, [lock_delay: String.t, ttl: String.t, behaviour: String.t]) :: {:ok, session_t} | error_reply_t
  def session_create(cfg, opts \\ [lock_delay: "15s", ttl: "60s", behaviour: "release"]) do
    params = %{"LockDelay" => Keyword.get(opts, :lock_delay, "15s"),
               "TTL" => Keyword.get(opts, :ttl, "60s"),
               "Behavior" => Keyword.get(opts, :behaviour, "release")} |> Poison.encode!
    path = "/v1/session/create"
    driver_req(cfg, :put, path, json_headers(), params, [])
    |> replyok_when(& &1[:status] == 200)
    |> case do
         {:ok, reply} ->
           reply[:payload]
           |> Poison.decode!
           |> Map.fetch("ID")
         error        -> error
       end
  end

  @doc """
  destroys a session.
  """
  @spec session_destroy(t, session_t) :: :ok | error_reply_t
  def session_destroy(cfg, session_id) do
    path = "/v1/session/destroy/#{session_id}"
    driver_req(cfg, :put, path, json_headers(), nil, [])
    |> replyok_when(& &1[:status] == 200)
    |> case do
         {:ok, _} -> :ok
         error    -> error
       end
  end

  @doc """
  information about the session
  """
  @spec session_info(t, session_t) :: {:ok, map()} | {:error, :not_found} | error_reply_t
  def session_info(cfg, session_id) do
    path = "/v1/session/info/#{session_id}"
    driver_req(cfg, :get, path, json_headers(), nil, [])
    |> replyok_when(& &1[:status] == 200)
    |> case do
         {:ok, reply} ->
           headers = reply
           |> Keyword.get(:headers, [])
           |> Enum.filter(fn {key, _} -> String.starts_with?(key, "x-consul-") end)
           |> Enum.into(%{})

           reply[:payload]
           |> Poison.decode!
           |> case do
                nil    -> {:error, :not_found}
                []     -> {:error, :not_found}
                [data] -> {:ok, data, headers}
              end
         error        -> error
       end
  end

  @doc """
  renews a session
  """
  @spec session_renew(t, session_t) :: :ok | error_reply_t
  def session_renew(cfg, session_id) do
    path = "/v1/session/renew/#{session_id}"
    driver_req(cfg, :put, path, json_headers(), nil, [])
    |> replyok_when(& &1[:status] == 200)
    |> case do
         {:ok, _} -> :ok
         error    -> error
       end
  end

  @doc """
  inserts a value into consul
  """
  @spec kv_put(t, String.t, binary) :: {:ok, any} | error_reply_t
  def kv_put(cfg, key, body) do
    path = "/v1/kv/#{key}"
    driver_req(cfg, :put, path, json_headers(), body, [])
    |> replyok_when(& &1[:status] == 200)
    |> case do
         {:ok, reply} -> {:ok, Poison.decode!(reply[:payload])}
         error        -> error
       end
  end

  @doc """
  retrieves values from consul
  """
  @spec kv_get(t, String.t) :: {:ok, any} | error_reply_t
  def kv_get(cfg, key) do
    path = "/v1/kv/#{key}"
    driver_req(cfg, :get, path, json_headers(), nil, [])
    |> replyok_when(& &1[:status] == 200)
    |> case do
         {:ok, reply} -> {:ok, Poison.decode!(reply[:payload])}
         error        -> error
       end
  end

  @doc """
  removes a key from consul
  """
  @spec kv_delete(t, String.t) :: :ok | error_reply_t
  def kv_delete(cfg, key) do
    path = "/v1/kv/#{key}"
    driver_req(cfg, :delete, path, json_headers(), nil, [])
    |> replyok_when(& &1[:status] == 200)
    |> case do
         {:ok, _} -> :ok
         error    -> error
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
