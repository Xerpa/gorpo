defmodule Gorpo.Drivers.HTTPC do
  @moduledoc """
  a driver that uses erlang's httpc library.
  """

  @type url_t     :: String.t
  @type method_t  :: :get | :put
  @type headers_t :: [{String.t, String.t}]
  @type payload_t :: binary | nil
  @type options_t :: [params: [{String.t, String.t}]]

  @type reply_t    :: {:ok, [status: integer,
                             headers: [{String.t, String.t}],
                             payload: binary]}
                      | {:error, :connect}
                      | {:error, :timeout}
                      | {:error, term}

  @spec new(
    [timeout: non_neg_integer, connect_timeout: non_neg_integer]
  ) :: (method_t, url_t, headers_t, payload_t, options_t -> reply_t)
  def new(options \\ []) do
    opts = options
    |> Keyword.put_new(:timeout, 30_000)
    |> Keyword.put_new(:connect_timeout, 5_000)
    |> Keyword.put(:autoredirect, false)
    fn method, url, headers, payload, options ->
      url = append_qstring(url, options[:params])
      request = if method in [:get, :head],
                  do: {encode_str(url), encode_str(headers)},
                  else: {encode_str(url), encode_str(headers), [], payload}
      do_request(method, request, opts)
    end
  end

  defp append_qstring(url, nil), do: url
  defp append_qstring(url, qs) when is_list(qs) do
    u = URI.parse(url)
    q = URI.encode_query(qs)
    case {u.query, q} do
      {nil, q1} -> %URI{u | query: q1}
      {"", q1}  -> %URI{u | query: q1}
      {q0, ""}  -> %URI{u | query: q0}
      {q0, q1}  -> %URI{u | query: q0 <> "&" <> q1}
    end
    |> to_string
  end

  defp do_request(method, request, opts) do
    :httpc.request(method, request, opts, [])
    |> wrap_reply
  end

  defp wrap_reply({:ok, {{_, status, _}, headers, payload}}) do
    charset = charset(headers)
    {:ok, [status: status,
           headers: Enum.map(headers, fn {k, v} -> {decode_str(k, nil), decode_str(v, nil)} end),
           payload: decode_str(payload, charset)]}
  end
  defp wrap_reply({:error, {:failed_connect, _}}), do: {:error, :connect}
  defp wrap_reply({:error, reason}), do: {:error, reason}

  defp encode_str(x) when is_binary(x), do: :binary.bin_to_list(x)
  defp encode_str(xs) when is_list(xs), do: Enum.map(xs, fn {k, v} -> {encode_str(k), encode_str(v)} end)
  defp encode_str(nil), do: []

  defp decode_str(x, nil), do: :binary.list_to_bin(x)
  defp decode_str(x, :utf8), do: :binary.list_to_bin(x)
  defp decode_str(x, charset), do: :unicode.characters_to_binary(x, charset, :utf8)

  defp charset(headers) do
    charsets = [{'charset=utf-8', :utf8},
                {'charset=utf8', :utf8},
                {'application/json', :utf8},
                {'charset=iso-8859-1', :latin1}]
    Enum.reduce(headers, nil, fn {k, v}, acc ->
      case :string.to_lower(k) do
        'content-type' ->
          v = :string.to_lower(v)
          Enum.reduce(charsets, acc, fn {name, charset}, acc ->
            if (:string.str(v, name) > 0),
              do: charset,
              else: acc
          end)
        _otherwise     -> acc
      end
    end)
  end
end
