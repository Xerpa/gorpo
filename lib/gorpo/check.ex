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
defmodule Gorpo.Check do
  @moduledoc """
  consul check definition

  <dl>
    <dt>ttl</dt>
    <dd>the timeout for a health check update. refer to
    https://golang.org/pkg/time/#ParseDuration for valid values;</dd>

    <dt>deregister_critical_service_after</dt>
    <dd>if a check is in critical state for more than this configure
    value then the service will be deregistered. refer to
    https://golang.org/pkg/time/#ParseDuration for valid values;</dd>
  </dl>
  """

  defstruct [ttl: "10s", deregister_critical_service_after: "10m"]

  @type t :: %__MODULE__{ttl: String.t,
                         deregister_critical_service_after: String.t}

  @doc """
  encodes the check into a map that once json-encoded matches the
  consul check definition specification.
  """
  @spec dump(t) :: map()
  def dump(check) do
    [{"TTL", check.ttl},
     {"DeregisterCriticalServiceAfter", check.deregister_critical_service_after}]
    |> Enum.filter(fn {_, x} -> not is_nil(x) end)
    |> Enum.into(%{})
  end

end

defimpl Poison.Encoder, for: Gorpo.Check do
  def encode(check, opts) do
    Poison.Encoder.encode(Gorpo.Check.dump(check), opts)
  end
end
