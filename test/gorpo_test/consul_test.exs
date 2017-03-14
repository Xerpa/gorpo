defmodule Gorpo.ConsulTest do
  use ExUnit.Case, async: true

  test "service_register" do
    driver  = Gorpo.Drivers.Echo.success([status: 200])
    agent   = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}
    service = %Gorpo.Service{id: "foobar", name: "foobar", check: %Gorpo.Check{}}

    {:ok, reply} = Gorpo.Consul.service_register(agent, service)
    assert "endpoint/v1/agent/service/register" == reply[:request][:url]
    assert Gorpo.Service.dump(service) == Poison.decode!(reply[:request][:payload])
    assert [params: [token: "token"]] == reply[:request][:options]
    assert :put == reply[:request][:method]
  end

  test "service_deregister" do
    driver  = Gorpo.Drivers.Echo.success([status: 200])
    agent   = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    {:ok, reply} = Gorpo.Consul.service_deregister(agent, "foobar")
    assert "endpoint/v1/agent/service/deregister/foobar" == reply[:request][:url]
    assert [params: [token: "token"]] == reply[:request][:options]
    assert :post == reply[:request][:method]
  end

  test "check_update" do
    driver   = Gorpo.Drivers.Echo.success([status: 200])
    agent    = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}
    status   = Enum.random([Gorpo.Status.passing, Gorpo.Status.warning, Gorpo.Status.critical])
    service  = %Gorpo.Service{id: "foobar", name: "foobar", check: %Gorpo.Check{}}
    check_id = Gorpo.Service.check_id(service)

    {:ok, reply} = Gorpo.Consul.check_update(agent, service, status)
    assert "endpoint/v1/agent/check/update/#{check_id}" == reply[:request][:url]
    assert Gorpo.Status.dump(status) == Poison.decode!(reply[:request][:payload])
    assert [params: [token: "token"]] == reply[:request][:options]
    assert :put == reply[:request][:method]
  end

  test "empty services" do
    driver  = Gorpo.Drivers.Echo.success([status: 200, payload: "[]"])
    agent   = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    {:ok, reply} = Gorpo.Consul.services(agent, "foobar")
    assert [] == reply
  end

  test "reply services with no checks" do
    service = %Gorpo.Service{id: "foobar", name: "foobar", port: 10, address: "localhost", tags: ["foo", "bar"]}
    payload = Poison.encode!([%{"Service" => service, "Checks" => []}])
    driver  = Gorpo.Drivers.Echo.success([status: 200, payload: payload])
    agent   = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    {:ok, reply} = Gorpo.Consul.services(agent, "foobar")
    assert [{service, nil}] == reply
  end

  test "single service and a single check" do
    status  = %Gorpo.Status{status: Enum.random([:passing, :warning, :critical])}
    service = %Gorpo.Service{id: "foobar", name: "foobar"}
    payload = Poison.encode!([%{"Service" => service, "Checks" => [%{"CheckID" => Gorpo.Service.check_id(service), "Status" => status.status}]}])
    driver  = Gorpo.Drivers.Echo.success([status: 200, payload: payload])
    agent   = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    {:ok, reply} = Gorpo.Consul.services(agent, "foobar")
    assert [{service, status}] == reply
  end

  test "multiple services and checks" do
    service_0 = %Gorpo.Service{id: "foobar_0", name: "foobar"}
    service_1 = %Gorpo.Service{id: "foobar_1", name: "foobar"}
    service_2 = %Gorpo.Service{id: "foobar_2", name: "foobar"}
    status_0  = %Gorpo.Status{status: :passing}
    status_1  = %Gorpo.Status{status: :warning}
    status_2  = %Gorpo.Status{status: :critical}
    payload   = Poison.encode!([%{"Service" => service_0,
                                  "Checks"  => [%{"CheckID" => "aaa"}, %{"CheckID" => Gorpo.Service.check_id(service_0), "Status" => status_0.status}]},
                                %{"Service" => service_1,
                                  "Checks"  => [%{"CheckID" => "bbb"}, %{"CheckID" => Gorpo.Service.check_id(service_1), "Status" => status_1.status}]},
                                %{"Service" => service_2,
                                  "Checks"  => [%{"CheckID" => "ccc"}, %{"CheckID" => Gorpo.Service.check_id(service_2), "Status" => status_2.status}]}])
    driver    = Gorpo.Drivers.Echo.success([status: 200, payload: payload])
    agent     = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    {:ok, reply} = Gorpo.Consul.services(agent, "foobar")
    assert [{service_0, status_0},
            {service_1, status_1},
            {service_2, status_2}] == reply
  end

  test "session create " do
    payload = Poison.encode!(%{"ID" => "foobar"})
    driver  = Gorpo.Drivers.Echo.success([status: 200, payload: payload])
    agent   = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    {:ok, reply} = Gorpo.Consul.session_create(agent)
    assert "foobar" == reply
  end

  test "session create (failure case)" do
    driver = Gorpo.Drivers.Echo.success([status: 500])
    agent  = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    assert :error == Gorpo.Consul.session_create(agent)
  end

  test "session renew" do
    driver = Gorpo.Drivers.Echo.success([status: 200])
    agent  = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    assert :ok == Gorpo.Consul.session_renew(agent, "foobar")
  end

  test "session renew (failure case)" do
    driver = Gorpo.Drivers.Echo.success([status: 500])
    agent  = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    assert :error == Gorpo.Consul.session_renew(agent, "foobar")
  end

  test "session destroy" do
    driver = Gorpo.Drivers.Echo.success([status: Enum.random([200, 400, 500])])
    agent  = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    assert :ok == Gorpo.Consul.session_destroy(agent, "foobar")
  end

  test "session destroy (failure case)" do
    driver = Gorpo.Drivers.Echo.failure(:no_reason)
    agent  = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    assert :error == Gorpo.Consul.session_destroy(agent, "foobar")
  end

  test "session info" do
    payload = %{"ID" => "foobar"}
    driver  = Gorpo.Drivers.Echo.success([status: 200, payload: Poison.encode!(payload)])
    agent   = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    assert {:ok, payload} == Gorpo.Consul.session_info(agent, "foobar")
  end

  test "session info (not found)" do
    driver = Gorpo.Drivers.Echo.success([status: 200, payload: "null"])
    agent  = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    assert {:error, :not_found} == Gorpo.Consul.session_info(agent, "foobar")
  end

  test "session info (other errors)" do
    driver = Gorpo.Drivers.Echo.success([status: 500])
    agent  = %Gorpo.Consul{endpoint: "endpoint", token: "token", driver: driver}

    assert :error == Gorpo.Consul.session_info(agent, "foobar")
  end
end
