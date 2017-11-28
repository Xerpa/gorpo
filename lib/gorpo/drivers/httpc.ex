defmodule Gorpo.Drivers.HTTPC do
  @moduledoc """
  A driver that uses erlang's httpc library.
  """

  @type url :: String.t
  @type method :: :get | :put
  @type headers :: [{String.t, String.t}]
  @type payload :: binary | nil
  @type options :: [params: [{String.t, String.t}]]

  @typep charset :: :utf8 | :latin1

  @type request_options :: [request_option]
  @type request_option ::
    {:timeout, non_neg_integer | :infinity}
    | {:connect_timeout, non_neg_integer | :infinity}

  @type reply ::
    {:ok, [status: integer, headers: [{String.t, String.t}],  payload: binary]}
    | {:error, :connect}
    | {:error, :timeout}
    | {:error, term}


  @spec new(request_options) :: ((method, url, headers, payload, options) -> reply)
  def new(options \\ []) do
    opts =
      options
      |> Keyword.put_new(:timeout, 30_000)
      |> Keyword.put_new(:connect_timeout, 5_000)
      |> Keyword.put(:autoredirect, false)

    fn method, url, headers, payload, options ->
      url = append_qstring(url, options[:params])
      content_type = Enum.find(headers, fn {k, _} ->
        String.downcase(k) == "content-type"
      end)

      content_type = case content_type do
        {_, value} ->
          encode_str(value)
        nil ->
          []
      end

      request =
        method in [:get, :head]
        && {encode_str(url), encode_str(headers)}
        || {encode_str(url), encode_str(headers), content_type, payload}

      do_request(method, request, opts)
    end
  end

  @spec append_qstring(url, [{term, term}] | nil) :: url
  defp append_qstring(url, nil),
    do: url
  defp append_qstring(url, qs) when is_list(qs) do
    uri = URI.parse(url)
    querystring = URI.encode_query(qs)

    uri = case {uri.query, querystring} do
      {nil, q1} ->
        %URI{uri | query: q1}
      {"", q1} ->
        %URI{uri | query: q1}
      {q0, ""} ->
        %URI{uri | query: q0}
      {q0, q1} ->
        %URI{uri | query: q0 <> "&" <> q1}
    end

    to_string(uri)
  end

  @spec do_request(method, request :: tuple, request_options) :: reply
  defp do_request(method, request, opts) do
    method
    |> :httpc.request(request, opts, [])
    |> wrap_reply()
  end

  defp wrap_reply({:error, {:failed_connect, _}}),
    do: {:error, :connect}
  defp wrap_reply({:error, reason}),
    do: {:error, reason}
  defp wrap_reply({:ok, {{_, status, _}, headers, payload}}) do
    charset = charset(headers)
    reply = [
      status: status,
      headers: Enum.map(headers, fn {k, v} ->
        {decode_str(k, nil), decode_str(v, nil)}
      end),
      payload: decode_str(payload, charset)
    ]

    {:ok, reply}
  end

  @spec encode_str(String.t | [{String.t, term}] | nil) :: charlist
  defp encode_str(nil),
    do: []
  defp encode_str(x) when is_binary(x),
    do: :binary.bin_to_list(x)
  defp encode_str(xs) when is_list(xs),
    do: Enum.map(xs, fn {k, v} -> {encode_str(k), encode_str(v)} end)


  @spec decode_str(charlist, charset | nil) :: String.t
  defp decode_str(x, nil),
    do: :binary.list_to_bin(x)
  defp decode_str(x, :utf8),
    do: :binary.list_to_bin(x)
  defp decode_str(x, charset),
    do: :unicode.characters_to_binary(x, charset, :utf8)

  @spec charset([{charlist, term}]) :: charset | nil
  defp charset(headers) do
    charsets = %{
      'charset=utf-8' =>
        :utf8,
      'charset=utf8' =>
        :utf8,
      'application/json' =>
        :utf8,
      'charset=iso-8859-1' =>
        :latin1
    }

    Enum.find_value(headers, fn {header, value} ->
      if :string.to_lower(header) == 'content-type' do
        Map.get(charsets, :string.to_lower(value))
      end
    end)
  end
end
