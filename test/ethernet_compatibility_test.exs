defmodule EthernetCompatibilityTest do
  use ExUnit.Case
  alias VintageNet.Interface.RawConfig
  alias VintageNet.Technology.Ethernet

  #
  # These tests ensure that VintageNet.Technology.Ethernet users get updated properly.
  # This is super-important to keep for a while so that pre-0.7.0 users are not broken.
  #
  test "ethernet configurations are normalized to VintageNetEthernet" do
    input = %{type: VintageNet.Technology.Ethernet, random_field: 42}

    assert Ethernet.normalize(input) == %{
             type: VintageNetEthernet,
             ipv4: %{method: :dhcp},
             random_field: 42
           }
  end

  test "create a ethernet configuration" do
    input = %{type: Ethernet, ipv4: %{method: :dhcp}, hostname: "unit_test"}

    output = Ethernet.to_raw_config("eth0", input, Utils.default_opts())
    normalized_input = Ethernet.normalize(input)

    expected = %RawConfig{
      ifname: "eth0",
      type: VintageNetEthernet,
      source_config: normalized_input,
      required_ifnames: ["eth0"],
      child_specs: [
        Utils.udhcpc_child_spec("eth0", "unit_test"),
        {VintageNet.Interface.InternetConnectivityChecker, "eth0"}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "eth0", "label", "eth0"]},
        {:run, "ip", ["link", "set", "eth0", "down"]}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "eth0", "up"]}]
    }

    assert expected == output
  end
end
