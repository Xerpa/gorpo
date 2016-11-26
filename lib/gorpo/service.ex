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
  consul service definition.

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

  defstruct [id: nil, name: nil, address: nil, port: nil, tags: nil, check: nil]

  @type t :: %__MODULE__{id: String.t,
                         name: String.t,
                         address: String.t | nil,
                         port: integer | nil,
                         tags: [String.t] | nil,
                         check: Gorpo.Check.t | nil}

  @doc """
  encodes the service into a map that once json-encoded matches the
  consul service definition specification.
  """
  @spec dump(t) :: map()
  def dump(service) do
    [{"ID", service.id},
     {"Name", service.name},
     {"Tags", service.tags},
     {"Port", service.port},
     {"Address", service.address},
     {"check", (if service.check, do: Gorpo.Check.dump(service.check))}]
    |> Enum.filter(fn {_, x} -> not is_nil(x) end)
    |> Enum.into(%{})
  end

  @doc """
  parses a consul service definition into a `Service` struct.
  """
  @spec load(String.t, map) :: t
  def load(name, data) do
    struct(__MODULE__,
      id: data["ID"],
      name: Map.get(data, "Name", name),
      port: data["Port"],
      tags: data["Tags"],
      address: data["Address"])
  end

  @doc """
  returns the id that can be used to refer to a check assoaciated with
  a given service.
  """
  @spec check_id(t) :: String.t | nil
  def check_id(service) do
    if service.id || service.name,
      do: "service:" <> (service.id || service.name)
  end

  @doc """
  returns the service id
  """
  @spec id(t) :: term
  def id(service), do: {service.id, service.name}
end

defimpl Poison.Encoder, for: Gorpo.Service do
  def encode(service, opts) do
    Poison.Encoder.encode(Gorpo.Service.dump(service), opts)
  end
end
