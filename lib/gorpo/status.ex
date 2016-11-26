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

  @type t :: %__MODULE__{status: :passing | :warning | :critical,
                         output: String.t | nil}

  @doc """
  a status that is `passing`
  """
  @spec passing(String.t | nil) :: t
  def passing(output \\ nil), do: struct(__MODULE__, status: :passing, output: output)

  @doc """
  a status that is `warning`
  """
  @spec warning(String.t | nil) :: t
  def warning(output \\ nil), do: struct(__MODULE__, status: :warinig, output: output)

  @doc """
  a status that is `critical`
  """
  @spec critical(String.t | nil) :: t
  def critical(output \\ nil), do: struct(__MODULE__, status: :critical, output: output)

  @doc """
  encodes the status into a map that once json-encoded matches the
  consul status definition specification.
  """
  @spec dump(t) :: map()
  def dump(status) do
    %{"Status" => to_string(status.status),
      "Output" => status.output}
  end

  @doc """
  parses a consul status definition into a `Status` struct
  """
  def load(data) do
    struct(__MODULE__,
      status: case data["Status"] do
                "passing"  -> :passing
                "warning"  -> :warning
                "critical" -> :critical
              end,
      output: data["Output"])
  end
end

defimpl Poison.Encoder, for: Gorpo.Status do
  def encode(status, opts) do
    Poison.Encoder.encode(Gorpo.Status.dump(status), opts)
  end
end
