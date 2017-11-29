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
  Consul API interface.
  """

  defstruct [:endpoint, :token, :driver]

  @type url :: String.t
  @type method :: :get | :put
  @type options :: keyword
  @type headers :: list
  @type payload :: binary | nil

  @type filter ::
    {:dc, String.t}
    | {:tag, String.t}
    | {:near, boolean}
    | {:status, :passing}

  @type reply :: error_reply | ok_reply
  @type ok_reply :: {:ok, [payload: term, headers: keyword, status: integer]}
  @type error_reply :: {:error, {:http, [payload: term, headers: keyword, status: integer]}} | {:error, {:driver, any}}
  @type t :: %__MODULE__{
    endpoint: String.t,
    token: String.t | nil,
    driver: ((method, url, headers, payload, options) -> reply)
  }

  @type session :: String.t

  @spec services(t, String.t, [filter]) :: {:ok, [{Gorpo.Node.t, Gorpo.Service.t, Gorpo.Status.status | nil}]} | error_reply
  @doc """
  search for services.

  * `filters`: restrict the search result. it is a keyword list with any
    combination of the following:

       + `dc `: only services on this datacenter;

       + `tag `: only services with the specified tag;

       + `near`: sort output by proximity to this agent;

       + `status`: only services that have this state;

  """
  def services(consul, service_name, filters \\ []) do
    path = "/v1/health/service/#{service_name}"
    params = Enum.reduce(filters, [], fn
      {:near, true}, acc ->
        [{:near, :_agent} | acc]
      {:near, false}, acc ->
        acc
      {:tag, tag}, acc when is_binary(tag) ->
        [{:tag, tag} | acc]
      {:dc, dc}, acc when is_binary(dc) ->
        [{:dc, dc} | acc]
      {:status, :passing}, _ ->
        [{:passing, nil}]
    end)

    headers = [{"accept", "application/json"}]
    result =
      consul
      |> driver_req(:get, path, headers, nil, params: params)
      |> replyok_when(& &1[:status] == 200)

    case result do
      {:ok, reply} ->
        services =
          reply[:payload]
          |> Poison.decode!()
          |> Enum.map(& load_service(service_name, &1))

        {:ok, services}
      reply ->
        reply
    end
  end

  @spec service_register(t, Gorpo.Service.t) :: reply
  @doc """
  Register/update a service.
  """
  def service_register(consul, service) do
    path = "/v1/agent/service/register"
    json = Poison.encode!(service)

    consul
    |> driver_req(:put, path, json_headers(), json, [])
    |> replyok_when(& &1[:status] == 200)
  end

  @spec service_deregister(t, String.t) :: reply
  @doc """
  Unregister a service.
  """
  def service_deregister(consul, service_id) do
    path = "/v1/agent/service/deregister/#{service_id}"

    consul
    |> driver_req(:post, path, json_headers(), nil, [])
    |> replyok_when(& &1[:status] == 200)
  end

  @spec check_update(t, Gorpo.Service.t, Gorpo.Status.t) :: ok_reply | {:error, :not_found}
  @doc """
  update health check status for a given service.
  """
  def check_update(consul, service, status) do
    check_id = Gorpo.Service.check_id(service)

    if check_id do
      json = Poison.encode!(status)
      path = "/v1/agent/check/update/#{check_id}"

      consul
      |> driver_req(:put, path, json_headers(), json, [])
      |> replyok_when(& &1[:status] == 200)
    else
      {:error, :not_found}
    end
  end

  @spec session_create(t, [lock_delay: String.t, ttl: String.t, behaviour: String.t]) :: {:ok, session} | error_reply
  @doc """
  Acquires a new session using the TTL method.
  """
  def session_create(consul, opts \\ [lock_delay: "15s", ttl: "60s", behaviour: "release"]) do
    params = %{
      "LockDelay" => Keyword.get(opts, :lock_delay, "15s"),
      "TTL" => Keyword.get(opts, :ttl, "60s"),
      "Behavior" => Keyword.get(opts, :behaviour, "release")
    }
    params = Poison.encode!(params)

    path = "/v1/session/create"

    result =
      consul
      |> driver_req(:put, path, json_headers(), params, [])
      |> replyok_when(& &1[:status] == 200)

    case result do
      {:ok, reply} ->
        reply[:payload]
        |> Poison.decode!
        |> Map.fetch("ID")
      error ->
        error
    end
  end

  @spec session_destroy(t, session) :: :ok | error_reply
  @doc """
  Destroys a session.
  """
  def session_destroy(consul, session_id) do
    path = "/v1/session/destroy/#{session_id}"

    result =
      consul
      |> driver_req(:put, path, json_headers(), nil, [])
      |> replyok_when(& &1[:status] == 200)

    case result do
      {:ok, _} ->
        :ok
      error ->
        error
    end
  end

  @spec session_info(t, session) :: {:ok, map} | {:error, :not_found} | error_reply
  @doc """
  Returns information about the session.
  """
  def session_info(consul, session_id) do
    path = "/v1/session/info/#{session_id}"

    result =
      consul
      |> driver_req(:get, path, json_headers(), nil, [])
      |> replyok_when(& &1[:status] == 200)

    case result do
      {:ok, reply} ->
        headers =
          reply
          |> Keyword.get(:headers, [])
          |> Enum.filter(fn {key, _} -> String.starts_with?(key, "x-consul-") end)
          |> Map.new()

        case Poison.decode!(reply[:payload]) do
          nil ->
            {:error, :not_found}
          [] ->
            {:error, :not_found}
          [data] ->
            {:ok, data, headers}
        end
      error ->
        error
    end
  end

  @spec session_renew(t, session) :: :ok | error_reply
  @doc """
  Renews a session.
  """
  def session_renew(consul, session_id) do
    path = "/v1/session/renew/#{session_id}"

    result =
      consul
      |> driver_req(:put, path, json_headers(), nil, [])
      |> replyok_when(& &1[:status] == 200)

    case result do
      {:ok, _} ->
        :ok
      error ->
        error
    end
  end

  @spec kv_put(t, String.t, binary) :: {:ok, term} | error_reply
  @doc """
  Inserts a value into consul.
  """
  def kv_put(consul, key, body) do
    path = "/v1/kv/#{key}"

    result =
      consul
      |> driver_req(:put, path, json_headers(), body, [])
      |> replyok_when(& &1[:status] == 200)

    case result do
      {:ok, reply} ->
        {:ok, Poison.decode!(reply[:payload])}
      error ->
        error
    end
  end

  @spec kv_get(t, String.t) :: {:ok, term} | error_reply
  @doc """
  Retrieves values from consul.
  """
  def kv_get(consul, key) do
    path = "/v1/kv/#{key}"

    result =
      consul
      |> driver_req(:get, path, json_headers(), nil, [])
      |> replyok_when(& &1[:status] == 200)

    case result do
      {:ok, reply} ->
        {:ok, Poison.decode!(reply[:payload])}
      error ->
        error
    end
  end

  @spec kv_delete(t, String.t) :: :ok | error_reply
  @doc """
  Removes a key from consul.
  """
  def kv_delete(consul, key) do
    path = "/v1/kv/#{key}"

    result =
      consul
      |> driver_req(:delete, path, json_headers(), nil, [])
      |> replyok_when(& &1[:status] == 200)

    case result do
      {:ok, _} ->
        :ok
      error ->
        error
    end
  end

  defp json_headers do
    [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]
  end

  defp driver_req(consul, method, path, headers, nil, options),
    do: driver_req(consul, method, path, headers, "", options)
  defp driver_req(consul, method, path, headers, payload, options) do
    url = String.trim_trailing(consul.endpoint, "/") <> "/" <> String.trim_leading(path, "/")

    opts =
      consul.token
      && Keyword.update(options, :params, [token: consul.token], & Keyword.put_new(&1, :token, consul.token))
      || options

    consul.driver.(method, url, headers, payload, opts)
  end

  @spec replyok_when(term, ((term) -> boolean)) :: {:ok, term} | {:error, term}
  defp replyok_when(reply, predicate) do
    case reply do
      {:ok, reply} ->
        predicate.(reply)
        && {:ok, reply}
        || {:error, reply}
      error ->
        error
    end
  end

  @spec load_service(String.t, map) :: {Gorpo.Node.t, Gorpo.Service.t, Gorpo.Status.t | nil}
  defp load_service(name, data) do
    node = Gorpo.Node.load(Map.fetch!(data, "Node"))
    service_address = fn address ->
      if address == "" or is_nil(address) do
        node.address
      else
        address
      end
    end

    service =
      name
      |> Gorpo.Service.load(Map.fetch!(data, "Service"))
      |> Map.update!(:address, service_address)

    result =
      data
      |> Map.fetch!("Checks")
      |> Enum.filter(& Map.get(&1, "CheckID") == Gorpo.Service.check_id(service))
      |> Enum.map(& Gorpo.Status.load/1)

    case result do
      [] ->
        {node, service, nil}
      [status] ->
        {node, service, status}
    end
  end
end
