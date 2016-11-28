defmodule Gorpo.Announce.UnitTest do
  use ExUnit.Case, async: true

  doctest Gorpo.Announce.Unit

  defp state(opts \\ []) do
    default_service = %Gorpo.Service{id: "foobar", name: "foobar", check: %Gorpo.Check{}}
    default_consul  = %Gorpo.Consul{driver: Gorpo.Drivers.Echo.success([status: 200]), endpoint: "http://localhost:8500"}
    [consul: Keyword.get(opts, :consul, default_consul),
     service: Keyword.get(opts, :service, default_service)]
  end

  test "announce without check" do
    service = %Gorpo.Service{}
    {:ok, state} = Gorpo.Announce.Unit.init(state(service: service))
    assert (5 * 60 * 1000) == state[:tick]
  end

  test "announce tick with check" do
    for {ttl, expect} <- [{"1h", 3600 * 200},
                          {"1m", 60 * 200},
                          {"1s", 200},
                          {"570", 114},
                          {"100", 50}] do
      service = %Gorpo.Service{id: "foobar", name: "foobar", check: %Gorpo.Check{ttl: ttl}}
      {:ok, state} = Gorpo.Announce.Unit.init(state(service: service))
      assert expect == state[:tick]
      assert expect == state[:wait]
    end
  end

  test "success initialization" do
    {:ok, state}      = Gorpo.Announce.Unit.init(state)
    {:reply, stat, _} = Gorpo.Announce.Unit.handle_call(:stat, nil, state)
    assert state[:wait] == state[:tick]
    assert :ok == stat[:service]
    assert :ok == stat[:heartbeat]
  end

  test "failure initialization" do
    consul = %Gorpo.Consul{driver: Gorpo.Drivers.Echo.success([status: 500]), endpoint: "http://localhost:8500"}

    {:ok, state}      = Gorpo.Announce.Unit.init(state(consul: consul))
    {:reply, stat, _} = Gorpo.Announce.Unit.handle_call(:stat, nil, state)
    assert state[:wait] > state[:tick]
    assert :error == stat[:service]
    assert :error == stat[:heartbeat]
  end
end
