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
defmodule Gorpo.Status do
  @moduledoc """
  consul status definition

  <dl>
    <dt>status</dt>
    <dd>one of `passing`, `warning`, `critical`</dd>

    <dt>output</dt>
    <dd>an opaque string;</dd>
  </dl>
  """

  defstruct [:status, :output]

  @type output :: String.t | nil
  @type status :: :passing | :warning | :critical
  @type t :: %__MODULE__{
    status: status,
    output: output
  }

  @spec passing(output) :: t
  @doc """
  A status that is `passing`.
  """
  def passing(output \\ nil),
    do: %__MODULE__{status: :passing, output: output}

  @spec warning(output) :: t
  @doc """
  A status that is `warning`.
  """
  def warning(output \\ nil),
    do: %__MODULE__{status: :warning, output: output}

  @spec critical(output) :: t
  @doc """
  A status that is `critical`.
  """
  def critical(output \\ nil),
    do: %__MODULE__{status: :critical, output: output}

  @spec dump(t) :: %{String.t => term}
  @doc """
  Encodes the status into a map that, once json-encoded, matches the Consul
  status definition specification.
  """
  def dump(status) do
    %{
      "Status" => to_string(status.status),
      "Output" => status.output
    }
  end

  @spec load(%{String.t => term}) :: t
  @doc """
  Parses a consul status definition into a `Status` struct.
  """
  def load(data) do
    status = case data["Status"] do
      "passing" ->
        :passing
      "warning" ->
        :warning
      "critical" ->
        :critical
    end

    %__MODULE__{
      status: status,
      output: data["Output"]
    }
  end
end

defimpl Poison.Encoder, for: Gorpo.Status do
  def encode(status, opts) do
    status
    |> Gorpo.Status.dump()
    |> Poison.Encoder.encode(opts)
  end
end
