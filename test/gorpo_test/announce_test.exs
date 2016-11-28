defmodule Gorpo.AnnounceTest do
  use ExUnit.Case, async: false

  doctest Gorpo.Announce

  setup do
    GenServer.call(Gorpo.Announce, :killall)
  end

  test "register a service twice" do
    service = %Gorpo.Service{id: "foo", name: "bar"}
    assert :ok == Gorpo.Announce.register(service)
  end

  test "unregister an unknown service" do
    service = %Gorpo.Service{id: "foo", name: "bar"}
    assert {:error, :not_found} == Gorpo.Announce.unregister(service)
  end

  test "unregister after register" do
    service = %Gorpo.Service{id: "foo", name: "bar"}
    assert :ok == Gorpo.Announce.register(service)
    assert :ok == Gorpo.Announce.unregister(service)
    assert {:error, :not_found} == Gorpo.Announce.unregister(service)
  end

  test "whereis an unknown service" do
    service = %Gorpo.Service{id: "foo", name: "bar"}
    assert :unknown == Gorpo.Announce.whereis(service)
  end

  test "whereis after register" do
    service = %Gorpo.Service{id: "foo", name: "bar"}
    assert :ok == Gorpo.Announce.register(service)
    assert is_pid(Gorpo.Announce.whereis(service))
  end

  test "whereis after unregister" do
    service = %Gorpo.Service{id: "foo", name: "bar"}
    assert :ok == Gorpo.Announce.register(service)
    assert :ok == Gorpo.Announce.unregister(service)
    assert :unknown == Gorpo.Announce.whereis(service)
  end
end
