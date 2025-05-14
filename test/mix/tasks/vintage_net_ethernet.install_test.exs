defmodule Mix.Tasks.VintageNetEthernet.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.VintageNetEthernet.Install

  doctest Install

  describe inspect(&Install.run/1) do
    test "sets up when config does not exist yet" do
      assert {:ok, igniter, _} =
               test_project()
               |> Igniter.compose_task("vintage_net_ethernet.install", ["--interface", "eth0"])
               |> assert_creates("config/target.exs", """
               import Config
               config :vintage_net, config: [{"eth0", %{type: VintageNetEthernet}}]
               """)
               |> apply_igniter()

      igniter
      |> Igniter.compose_task("vintage_net_ethernet.install", ["--interface", "eth0"])
      |> assert_unchanged()
    end

    test "sets up when config already contains other interfaces" do
      test_project(
        files: %{
          "config/target.exs" => """
          import Config

          config :vintage_net,
            config: [{"wlan0", %{type: VintageNetWiFi}}]
          """
        }
      )
      |> Igniter.compose_task("vintage_net_ethernet.install", ["--interface", "eth0"])
      |> assert_has_patch("config/target.exs", """
          ...|
       2 2   |
       3 3   |config :vintage_net,
       4   - |  config: [{"wlan0", %{type: VintageNetWiFi}}]
         4 + |  config: [{"wlan0", %{type: VintageNetWiFi}}, {"eth0", %{type: VintageNetEthernet}}]
      """)
    end
  end
end
