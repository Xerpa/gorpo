defmodule Gorpo.Drivers.EchoTest do
  use ExUnit.Case

  test "failure" do
    driver = Gorpo.Drivers.Echo.failure(:foobar)
    assert {:error, {:foobar, [url: :url,
                               method: :method,
                               headers: :headers,
                               payload: :payload,
                               options: :options]}} == driver.(:method, :url, :headers, :payload, :options)
  end

  test "success" do
    driver = Gorpo.Drivers.Echo.success(status: :status, payload: :payload0)
    assert {:ok, [status: :status,
                  payload: :payload0,
                  request: [url: :url,
                            method: :method,
                            headers: :headers,
                            payload: :payload,
                            options: :options]]} == driver.(:method, :url, :headers, :payload, :options)
  end
end
