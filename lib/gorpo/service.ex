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
defmodule Gorpo.Service do
  @moduledoc """
  Consul service definition.

  <dl>
    <dt>id</dt>
    <dd>a unique value for this service on the local agent</dd>

    <dt>name</dt>
    <dd>the name of this service</dd>

    <dt>tags</dt>
    <dd>a list of strings [opaque to consul] that can be used to further assist discovery</dd>

    <dt>address</dt>
    <dd>hostname of IP address of this service. if not used, the agent's IP address is used</dd>

    <dt>port</dt>
    <dd>the inet port of this service</dd>

    <dt>check</dt>
    <dd>the health check associated with this service</dd>
  </dl>
  """

  defstruct [
    id: nil,
    name: nil,
    address: nil,
    port: nil,
    tags: [],
    check: nil
  ]

  @type t :: %__MODULE__{
    id: String.t,
    name: String.t,
    address: String.t | nil,
    port: 0..65_535 | nil,
    tags: [String.t],
    check: Gorpo.Check.t | nil
  }

  @spec dump(t) :: %{String.t => term}
  @doc """
  Encodes the service into a map that once json-encoded matches the Consul
  service definition specification.
  """
  def dump(service) do
    check = if service.check, do: Gorpo.Check.dump(service.check)

    params = [
      {"ID", service.id},
      {"Name", service.name},
      {"Tags", service.tags},
      {"Port", service.port},
      {"Address", service.address},
      {"check", check}
    ]

    params
    |> Enum.reject(fn {_, x} -> is_nil(x) end)
    |> Map.new()
  end

  @spec load(String.t, map) :: t
  @doc """
  Parses a Consul service definition into a `Service` struct.
  """
  def load(name, data) do
    %__MODULE__{
      id: data["ID"],
      name: Map.get(data, "Name", name),
      port: data["Port"],
      tags: Map.get(data, "Tags", []),
      address: data["Address"]
    }
  end

  @spec check_id(t) :: String.t | nil
  @doc """
  Returns the id that can be used to refer to a check assoaciated with a given
  service.
  """
  def check_id(service) do
    if service.id || service.name do
      "service:" <> (service.id || service.name)
    end
  end

  @doc """
  Returns the service id.
  """
  @spec id(t) :: {String.t, String.t | nil}
  def id(%__MODULE__{id: id, name: name}),
    do: {id, name}
end

defimpl Poison.Encoder, for: Gorpo.Service do
  def encode(service, opts) do
    service
    |> Gorpo.Service.dump()
    |> Poison.Encoder.encode(opts)
  end
end
