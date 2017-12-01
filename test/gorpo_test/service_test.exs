defmodule Gorpo.ServiceTest do
  use ExUnit.Case, async: false

  alias Gorpo.Service

  test "tags is an empty list by default"  do
    assert %Service{tags: []} == Service.load(nil, %{})
    assert %Service{tags: :tags} == Service.load(nil, %{"Tags" => :tags})
  end

  test "load . dump = id" do
    service = %Service{
      id: "id",
      name: "name",
      tags: ["m", "e", "h"],
      port: 42,
      address: "x.x.x.x"
    }
    assert service == Service.load(service.name, Service.dump(service))
  end

  test "load . Poison.decode . Poison.dump = id" do
    service = %Service{
      id: "id",
      name: "name",
      tags: ["m", "e", "h"],
      port: 42,
      address: "x.x.x.x"
    }
    assert service == Service.load(service.name, Poison.decode!(Poison.encode!(service)))
  end

  test "uses name when not defined in data" do
    assert %Service{name: "name"} == Service.load("name", %{})
  end
end
