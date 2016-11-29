defmodule Gorpo.Drivers.HTTPCTest do
  use ExUnit.Case

  setup do
    {:ok, [driver: Gorpo.Drivers.HTTPC.new(timeout: 1000)]}
  end

  @tag :external
  test "get method + params", %{driver: driver} do
    {:ok, reply} = driver.(:get, "https://httpbin.org/get?bar=foo", [], nil, [params: [foo: "bar"]])
    json = Poison.decode!(reply[:payload])
    assert %{"foo" => "bar", "bar" => "foo"} == json["args"]
  end

  @tag :external
  test "put method + params", %{driver: driver} do
    {:ok, reply} = driver.(:put, "https://httpbin.org/put?bar=foo", [], "☃", [params: [foo: "bar"]])
    json = Poison.decode!(reply[:payload])
    assert %{"foo" => "bar", "bar" => "foo"} == json["args"]
    assert "☃" == json["data"]
  end

  @tag :external
  test "headers are properly encoded", %{driver: driver} do
    {:ok, reply} = driver.(:get, "https://httpbin.org/headers", [{"foo", "☠"}, {"bar", "☃"}], nil, [])
    json = Poison.decode!(reply[:payload])
    assert "\u00e2\u0098\u00a0" == json["headers"]["Foo"]
    assert "\u00e2\u0098\u0083" == json["headers"]["Bar"]
  end

  @tag :external
  test "timeout", %{driver: driver} do
    assert {:error, :timeout} == driver.(:get, "https://httpbin.org/delay/2", [], nil, [])
  end
end
