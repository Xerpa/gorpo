defmodule Gorpo.Drivers.Echo do
  @moduledoc """
  A driver that echoes the input for testing purposes.
  """

  def failure(reason) do
    fn method, url, headers, payload, options ->
      reply = [
        url: url,
        method: method,
        headers: headers,
        payload: payload,
        options: options
      ]

      {:error, {reason, reply}}
    end
  end

  def success(options) do
    fn method, url, headers, r_payload, r_options ->
      reply = [
        status: options[:status],
        payload: options[:payload],
        request: [
          url: url,
          method: method,
          headers: headers,
          payload: r_payload,
          options: r_options
        ]
      ]

      {:ok, reply}
    end
  end
end
