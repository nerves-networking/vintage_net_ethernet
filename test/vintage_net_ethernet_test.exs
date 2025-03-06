# SPDX-FileCopyrightText: 2019 Jon Carstens
# SPDX-FileCopyrightText: 2020 Frank Hunleth
# SPDX-FileCopyrightText: 2021 Connor Rigby
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetEthernetTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias VintageNet.Interface.RawConfig
  alias VintageNetEthernet, as: Ethernet

  test "create a wired ethernet configuration" do
    input = %{type: Ethernet, ipv4: %{method: :dhcp}, hostname: "unit_test"}

    output = %RawConfig{
      ifname: "eth0",
      type: Ethernet,
      source_config: input,
      required_ifnames: ["eth0"],
      child_specs: [
        Utils.udhcpc_child_spec("eth0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "eth0"}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip", ["link", "set", "eth0", "down"]}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "eth0", "up"]}]
    }

    assert output == Ethernet.to_raw_config("eth0", input, Utils.default_opts())
  end

  test "create a wired ethernet configuration with custom mac address" do
    input = %{
      type: Ethernet,
      mac_address: "11:22:33:44:55:66",
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "eth0",
      type: Ethernet,
      source_config: input,
      required_ifnames: ["eth0"],
      child_specs: [
        Utils.udhcpc_child_spec("eth0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "eth0"}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip", ["link", "set", "eth0", "down"]}
      ],
      up_cmds: [
        {:run, "ip", ["link", "set", "eth0", "address", "11:22:33:44:55:66"]},
        {:run, "ip", ["link", "set", "eth0", "up"]}
      ]
    }

    assert output == Ethernet.to_raw_config("eth0", input, Utils.default_opts())
  end

  test "raises on invalid MAC address" do
    assert_raise ArgumentError, fn ->
      Ethernet.normalize(%{type: Ethernet, mac_address: "11:22:33"})
    end

    assert_raise ArgumentError, fn ->
      Ethernet.normalize(%{type: Ethernet, mac_address: :bad_mac})
    end
  end

  test "create a wired ethernet configuration with custom mac address function" do
    input = %{
      type: Ethernet,
      mac_address: {__MODULE__, :return_a_mac, []},
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "eth0",
      type: Ethernet,
      source_config: input,
      required_ifnames: ["eth0"],
      child_specs: [
        Utils.udhcpc_child_spec("eth0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "eth0"}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip", ["link", "set", "eth0", "down"]}
      ],
      up_cmds: [
        {:run, "ip", ["link", "set", "eth0", "address", "12:34:56:78:9a:bc"]},
        {:run, "ip", ["link", "set", "eth0", "up"]}
      ]
    }

    assert output == Ethernet.to_raw_config("eth0", input, Utils.default_opts())
  end

  @doc false
  @spec return_a_mac() :: String.t()
  def return_a_mac() do
    "12:34:56:78:9a:bc"
  end

  test "ignores crashing custom mac address functions" do
    input = %{
      type: Ethernet,
      mac_address: {__MODULE__, :crash_a_mac, []},
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "eth0",
      type: Ethernet,
      source_config: input,
      required_ifnames: ["eth0"],
      child_specs: [
        Utils.udhcpc_child_spec("eth0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "eth0"}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip", ["link", "set", "eth0", "down"]}
      ],
      up_cmds: [
        {:run, "ip", ["link", "set", "eth0", "up"]}
      ]
    }

    logs =
      capture_log(fn ->
        assert output == Ethernet.to_raw_config("eth0", input, Utils.default_opts())
      end)

    assert logs =~ "ignoring invalid MAC address"
  end

  @doc false
  @spec crash_a_mac() :: no_return()
  def crash_a_mac() do
    raise RuntimeError, "crash_a_mac"
  end

  test "create a wired ethernet configuration with static IP" do
    input = %{
      type: Ethernet,
      ipv4: %{
        method: :static,
        address: "192.168.0.2",
        netmask: "255.255.255.0"
      },
      hostname: "unit_test"
    }

    output = %RawConfig{
      type: Ethernet,
      ifname: "eth0",
      source_config: %{
        hostname: "unit_test",
        type: Ethernet,
        ipv4: %{
          method: :static,
          address: {192, 168, 0, 2},
          prefix_length: 24
        }
      },
      required_ifnames: ["eth0"],
      child_specs: [{VintageNet.Connectivity.LANChecker, "eth0"}],
      down_cmds: [
        {:fun, VintageNet.RouteManager, :clear_route, ["eth0"]},
        {:fun, VintageNet.NameResolver, :clear, ["eth0"]},
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip", ["link", "set", "eth0", "down"]}
      ],
      up_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip",
         [
           "addr",
           "add",
           "192.168.0.2/24",
           "dev",
           "eth0",
           "broadcast",
           "192.168.0.255",
           "label",
           "eth0"
         ]},
        {:run, "ip", ["link", "set", "eth0", "up"]},
        {:fun, VintageNet.RouteManager, :clear_route, ["eth0"]},
        {:fun, VintageNet.NameResolver, :clear, ["eth0"]}
      ]
    }

    assert output == Ethernet.to_raw_config("eth0", input, Utils.default_opts())
  end

  test "create a dhcpd config" do
    input = %{
      type: Ethernet,
      ipv4: %{
        method: :static,
        address: "192.168.24.1",
        netmask: "255.255.255.0"
      },
      dhcpd: %{
        start: "192.168.24.2",
        end: "192.168.24.100"
      },
      hostname: "unit_test"
    }

    output = %RawConfig{
      type: Ethernet,
      ifname: "eth0",
      source_config: %{
        hostname: "unit_test",
        type: Ethernet,
        ipv4: %{
          method: :static,
          address: {192, 168, 24, 1},
          prefix_length: 24
        },
        dhcpd: %{start: {192, 168, 24, 2}, end: {192, 168, 24, 100}}
      },
      required_ifnames: ["eth0"],
      child_specs: [
        {VintageNet.Connectivity.LANChecker, "eth0"},
        Utils.udhcpd_child_spec("eth0")
      ],
      files: [
        {"/tmp/vintage_net/udhcpd.conf.eth0",
         """
         interface eth0
         pidfile /tmp/vintage_net/udhcpd.eth0.pid
         lease_file /tmp/vintage_net/udhcpd.eth0.leases
         notify_file #{Application.app_dir(:beam_notify, ["priv", "beam_notify"])}

         end 192.168.24.100
         start 192.168.24.2

         """}
      ],
      down_cmds: [
        {:fun, VintageNet.RouteManager, :clear_route, ["eth0"]},
        {:fun, VintageNet.NameResolver, :clear, ["eth0"]},
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip", ["link", "set", "eth0", "down"]}
      ],
      up_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip",
         [
           "addr",
           "add",
           "192.168.24.1/24",
           "dev",
           "eth0",
           "broadcast",
           "192.168.24.255",
           "label",
           "eth0"
         ]},
        {:run, "ip", ["link", "set", "eth0", "up"]},
        {:fun, VintageNet.RouteManager, :clear_route, ["eth0"]},
        {:fun, VintageNet.NameResolver, :clear, ["eth0"]}
      ]
    }

    assert output == Ethernet.to_raw_config("eth0", input, Utils.default_opts())
  end
end
