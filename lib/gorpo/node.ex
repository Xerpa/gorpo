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
defmodule Gorpo.Node do
  @moduledoc """
  Consul node information.

  <dl>
    <dt>id</dt>
    <dd>the node id</dd>

    <dt>node</dt>
    <dd>the name of the consul node</dd>

    <dt>address</dt>
    <dd>the ip address of the consul node</dd>

    <dt>tagged_addresses</dt>
    <dd>the list of explicit LAN and WAN IP addresses for the agent</dd>
  </dl>
  """

  defstruct [
    id: nil,
    node: nil,
    address: nil,
    tagged_addresses: %{
      lan: nil, wan: nil
    }
  ]

  @type t :: %__MODULE__{
    id: String.t | nil,
    node: String.t | nil,
    address: String.t | nil,
    tagged_addresses: %{lan: String.t | nil, wan: String.t | nil}
  }

  @spec dump(t) :: %{String.t => term}
  @doc """
  Encodes the node into a map that once json-encoded matches the Consul
  node structure.
  """
  def dump(node) do
    %{
      "ID" => node.id,
      "Node" => node.node,
      "Address" => node.address,
      "TaggedAddresses" => %{
        "lan" => node.tagged_addresses.lan,
        "wan" => node.tagged_addresses.wan
      }
    }
  end

  @spec load(map) :: t
  @doc """
  Parses a Consul service definition into a `Service` struct.
  """
  def load(data) do
    tagged_addresses = Map.get(data, "TaggedAddresses", %{})
    %__MODULE__{
      id: data["ID"],
      node: data["Node"],
      address: data["Address"],
      tagged_addresses: %{
        lan: tagged_addresses["lan"],
        wan: tagged_addresses["wan"]
      }
    }
  end
end

defimpl Poison.Encoder, for: Gorpo.Node do
  def encode(node, opts) do
    node
    |> Gorpo.Node.dump()
    |> Poison.Encoder.encode(opts)
  end
end
