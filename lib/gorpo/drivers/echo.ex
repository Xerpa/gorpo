defmodule Gorpo.Drivers.Echo do
  @moduledoc """
  a driver that echoes the input for testing purposes.
  """

  def failure(reason) do
    fn method, url, headers, payload, options ->
      {:error, {reason, [url: url,
                         method: method,
                         headers: headers,
                         payload: payload,
                         options: options]}}
    end
  end

  def success(options) do
    fn method, url, headers, r_payload, r_options ->
      {:ok, [status: options[:status],
             payload: options[:payload],
             request: [url: url,
                       method: method,
                       headers: headers,
                       payload: r_payload,
                       options: r_options]]}
    end
  end

end
