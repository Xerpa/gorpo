defmodule GorpoTest do
  use ExUnit.Case, async: true

  test "application gets started" do
    apps = Application.started_applications
    |> Enum.map(fn {k, _, _} -> k end)
    |> Enum.filter(& &1 == :gorpo)
    assert [:gorpo] == apps
  end

  test "gorpo.announce is running" do
    assert Process.alive?(Process.whereis(Gorpo.Announce))
  end

  # TODO:how to test Application.put_env?
end
