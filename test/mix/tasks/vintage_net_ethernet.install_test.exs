# SPDX-FileCopyrightText: 2025 Jonatan Männchen
# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetEthernet.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @nerves_new_config """
  import Config

  # Configure the network using vintage_net
  #
  # Update regulatory_domain to your 2-letter country code E.g., "US"
  #
  # See https://github.com/nerves-networking/vintage_net for more information
  config :vintage_net,
    regulatory_domain: "00",
    config: [
      {"usb0", %{type: VintageNetDirect}},
      {"eth0",
       %{
         type: VintageNetEthernet,
         ipv4: %{method: :dhcp}
       }},
      {"wlan0", %{type: VintageNetWiFi}}
    ]
  """

  @static_argv [
    "--ethernet-address",
    "192.168.9.232/24",
    "--ethernet-gateway",
    "192.168.9.1",
    "--ethernet-name-servers",
    "1.1.1.1,8.8.8.8"
  ]

  defp nerves_project(target_exs \\ "import Config\n") do
    test_project(files: %{"config/target.exs" => target_exs})
  end

  defp install(igniter, argv \\ []) do
    Igniter.compose_task(igniter, "vintage_net_ethernet.install", argv)
  end

  # Evaluate the generated config file and return the network interface
  # configurations the way that VintageNet gets them
  defp interface_configs(igniter, path \\ "config/target.exs") do
    content = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
    file = Path.join(System.tmp_dir!(), "vintage_net_ethernet_#{System.unique_integer()}.exs")

    try do
      File.write!(file, content)
      Config.Reader.read!(file)[:vintage_net][:config]
    after
      File.rm(file)
    end
  end

  test "adds eth0 with DHCP to config/target.exs in Nerves projects" do
    igniter =
      nerves_project()
      |> install()
      |> assert_has_patch("config/target.exs", """
      + |config :vintage_net, config: [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}]
      """)
      |> assert_unchanged("config/config.exs")

    assert igniter.notices == []
    assert igniter.warnings == []
    assert igniter.issues == []

    # This is the entry that `mix nerves.new` generates
    assert interface_configs(apply_igniter!(igniter)) ==
             [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}]
  end

  test "falls back to config/config.exs with a notice" do
    igniter =
      test_project()
      |> install()
      |> assert_creates("config/config.exs", """
      import Config
      config :vintage_net, config: [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}]
      """)
      |> refute_creates("config/target.exs")
      |> assert_has_notice(&(&1 =~ "config/target.exs was not found"))

    assert Enum.count(igniter.notices) == 1
  end

  test "is idempotent" do
    for argv <- [[], ["--ethernet-ifname", "end0"], @static_argv],
        project <- [nerves_project(), test_project()] do
      project
      |> install(argv)
      |> apply_igniter!()
      |> install(argv)
      |> assert_unchanged()
    end
  end

  test "keeps the config from mix nerves.new" do
    igniter = nerves_project(@nerves_new_config) |> install() |> assert_unchanged()

    assert igniter.notices == []
    assert igniter.warnings == []
  end

  test "keeps a customized eth0" do
    igniter =
      nerves_project("""
      import Config

      config :vintage_net,
        regulatory_domain: "US",
        config: [
          {"eth0",
           %{
             type: VintageNetEthernet,
             mac_address: {MyMacAddressReader, :read, []},
             ipv4: %{method: :static, address: "10.0.0.2", prefix_length: 8}
           }}
        ]
      """)
      |> install()
      |> assert_unchanged()

    assert igniter.notices == []
  end

  test "keeps an eth0 that uses another technology" do
    nerves_project("""
    import Config

    config :vintage_net, config: [{"eth0", %{type: VintageNetBridge}}]
    """)
    |> install()
    |> assert_unchanged()
  end

  test "appends to the other network interfaces" do
    nerves_project("""
    import Config

    config :vintage_net,
      regulatory_domain: "SE",
      config: [
        {"usb0", %{type: VintageNetDirect}},
        {"wlan0", %{type: VintageNetWiFi}}
      ]
    """)
    |> install()
    |> assert_has_patch("config/target.exs", """
      |    {"usb0", %{type: VintageNetDirect}},
    - |    {"wlan0", %{type: VintageNetWiFi}}
    + |    {"wlan0", %{type: VintageNetWiFi}},
    + |    {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}
    """)
  end

  test "adds to the base config from vintage_net.install" do
    nerves_project("""
    import Config

    config :vintage_net, regulatory_domain: "US", config: []
    """)
    |> install()
    |> assert_has_patch("config/target.exs", """
    - |config :vintage_net, regulatory_domain: "US", config: []
    + |config :vintage_net,
    + |  regulatory_domain: "US",
    + |  config: [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}]
    """)
  end

  test "warns when the network interfaces aren't a list" do
    nerves_project("""
    import Config

    config :vintage_net, regulatory_domain: "US", config: MyApp.Network.interfaces()
    """)
    |> install()
    |> assert_unchanged()
    |> assert_has_warning(&(&1 =~ ~s|could not add "eth0"|))
  end

  describe "--ethernet-ifname" do
    test "sets the interface name" do
      nerves_project(@nerves_new_config)
      |> install(["--ethernet-ifname", "eth1"])
      |> assert_has_patch("config/target.exs", """
      - |    {"wlan0", %{type: VintageNetWiFi}}
      + |    {"wlan0", %{type: VintageNetWiFi}},
      + |    {"eth1", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}
      """)
    end

    test "rejects invalid interface names" do
      for bad <- ["", "eth 0", "eth/0", "..", "averyveryverylongname"] do
        nerves_project()
        |> install(["--ethernet-ifname", bad])
        |> assert_unchanged()
        |> assert_has_issue(&(&1 =~ "invalid --ethernet-ifname"))
      end
    end
  end

  describe "static IPv4 options" do
    test "all of them" do
      igniter =
        nerves_project()
        |> install(@static_argv)
        |> assert_has_patch("config/target.exs", """
        + |config :vintage_net,
        + |  config: [
        + |    {"eth0",
        + |     %{
        + |       type: VintageNetEthernet,
        + |       ipv4: %{
        + |         method: :static,
        + |         address: "192.168.9.232",
        + |         prefix_length: 24,
        + |         gateway: "192.168.9.1",
        + |         name_servers: ["1.1.1.1", "8.8.8.8"]
        + |       }
        + |     }}
        + |  ]
        """)

      assert igniter.notices == []

      # Check that VintageNetEthernet accepts what was written
      assert [{"eth0", config}] = interface_configs(apply_igniter!(igniter))

      assert VintageNetEthernet.normalize(config) == %{
               type: VintageNetEthernet,
               ipv4: %{
                 method: :static,
                 address: {192, 168, 9, 232},
                 prefix_length: 24,
                 gateway: {192, 168, 9, 1},
                 name_servers: [{1, 1, 1, 1}, {8, 8, 8, 8}]
               }
             }
    end

    test "--ethernet-address with a prefix length is enough" do
      igniter = nerves_project() |> install(["--ethernet-address", "10.0.0.2/8"])

      assert interface_configs(apply_igniter!(igniter)) == [
               {"eth0",
                %{
                  type: VintageNetEthernet,
                  ipv4: %{method: :static, address: "10.0.0.2", prefix_length: 8}
                }}
             ]
    end

    test "--ethernet-netmask is converted to a prefix length" do
      igniter =
        nerves_project()
        |> install([
          "--ethernet-ifname",
          "eth1",
          "--ethernet-address",
          "172.16.5.4",
          "--ethernet-netmask",
          "255.255.240.0"
        ])

      assert [{"eth1", config}] = interface_configs(apply_igniter!(igniter))
      assert config.ipv4 == %{method: :static, address: "172.16.5.4", prefix_length: 20}
      assert VintageNetEthernet.normalize(config).ipv4.address == {172, 16, 5, 4}
    end

    test "--ethernet-name-servers accepts spaces and IPv6 addresses" do
      igniter =
        nerves_project()
        |> install([
          "--ethernet-address",
          "10.0.0.2/8",
          "--ethernet-name-servers",
          "1.1.1.1, 2606:4700:4700::1111"
        ])

      assert [{"eth0", config}] = interface_configs(apply_igniter!(igniter))
      assert config.ipv4.name_servers == ["1.1.1.1", "2606:4700:4700::1111"]

      assert VintageNetEthernet.normalize(config).ipv4.name_servers ==
               [{1, 1, 1, 1}, {0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111}]
    end

    test "are added next to other network interfaces" do
      igniter =
        nerves_project("""
        import Config

        config :vintage_net, regulatory_domain: "US", config: [{"wlan0", %{type: VintageNetWiFi}}]
        """)
        |> install(["--ethernet-address", "10.0.0.2/8"])

      assert [{"wlan0", %{type: VintageNetWiFi}}, {"eth0", %{ipv4: %{method: :static}}}] =
               interface_configs(apply_igniter!(igniter))
    end

    test "don't replace an existing configuration, but add a notice" do
      nerves_project(@nerves_new_config)
      |> install(@static_argv)
      |> assert_unchanged()
      |> assert_has_notice(fn notice ->
        notice =~ ~s|"eth0" is already configured in config/target.exs| and
          notice =~ ~s|address: "192.168.9.232"|
      end)
    end

    test "no notice when the existing configuration is the requested one" do
      igniter =
        nerves_project("""
        import Config

        config :vintage_net,
          regulatory_domain: "US",
          config: [
            {"eth0",
             %{
               type: VintageNetEthernet,
               ipv4: %{method: :static, address: "10.0.0.2", prefix_length: 8}
             }}
          ]
        """)
        |> install(["--ethernet-address", "10.0.0.2/8"])
        |> assert_unchanged()

      assert igniter.notices == []
    end

    test "require an address" do
      for argv <- [
            ["--ethernet-netmask", "255.255.255.0"],
            ["--ethernet-gateway", "192.168.9.1"],
            ["--ethernet-name-servers", "1.1.1.1"]
          ] do
        nerves_project()
        |> install(argv)
        |> assert_unchanged()
        |> assert_has_issue(&(&1 =~ "--ethernet-address is required"))
      end
    end

    test "require a subnet" do
      nerves_project()
      |> install(["--ethernet-address", "192.168.9.232"])
      |> assert_unchanged()
      |> assert_has_issue(&(&1 =~ "the subnet for --ethernet-address is missing"))
    end

    test "reject a prefix length and a netmask together" do
      nerves_project()
      |> install([
        "--ethernet-address",
        "192.168.9.232/24",
        "--ethernet-netmask",
        "255.255.255.0"
      ])
      |> assert_unchanged()
      |> assert_has_issue(&(&1 =~ "--ethernet-netmask can't be used"))
    end

    test "reject invalid addresses" do
      for bad <- [
            "",
            "192.168.9",
            "192.168.9.256/24",
            "192.168.9.232/33",
            "192.168.9.232/-1",
            "192.168.9.232/24/1",
            "192.168.9.232/2x",
            "fe80::1/64",
            "example.com/24"
          ] do
        nerves_project()
        |> install(["--ethernet-address", bad])
        |> assert_unchanged()
        |> assert_has_issue(&(&1 =~ "invalid --ethernet-address"))
      end
    end

    test "reject invalid netmasks" do
      for bad <- ["", "24", "255.255.0.255", "192.168.1.1", "ffff::"] do
        nerves_project()
        |> install(["--ethernet-address", "192.168.9.232", "--ethernet-netmask", bad])
        |> assert_unchanged()
        |> assert_has_issue(&(&1 =~ "invalid --ethernet-netmask"))
      end
    end

    test "reject invalid gateways" do
      for bad <- ["", "192.168.9", "gateway.local", "fe80::1"] do
        nerves_project()
        |> install(["--ethernet-address", "192.168.9.232/24", "--ethernet-gateway", bad])
        |> assert_unchanged()
        |> assert_has_issue(&(&1 =~ "invalid --ethernet-gateway"))
      end
    end

    test "reject invalid name servers" do
      for bad <- ["", "1.1.1.1,", "1.1.1.1;8.8.8.8", "dns.example.com", "1.1.1"] do
        nerves_project()
        |> install(["--ethernet-address", "192.168.9.232/24", "--ethernet-name-servers", bad])
        |> assert_unchanged()
        |> assert_has_issue(&(&1 =~ "invalid --ethernet-name-servers"))
      end
    end
  end

  describe "restricting the dependency to the project's targets" do
    defp targets_mix_exs(deps) do
      """
      defmodule Test.MixProject do
        use Mix.Project

        @app :test
        @device_targets [:rpi4, :rpi5]
        @other_targets [:bbb]

        def project do
          [app: @app, version: "0.1.0", deps: deps()]
        end

        defp deps do
          [
            {:nerves, "~> 2.0", runtime: false},
            #{Enum.join(deps, ",\n      ")}
          ]
        end
      end
      """
    end

    defp targets_install(deps) do
      test_project(
        files: %{"mix.exs" => targets_mix_exs(deps), "config/target.exs" => "import Config\n"}
      )
      |> Igniter.compose_task("vintage_net_ethernet.install", [])
    end

    defp targets_mix_exs_after(igniter) do
      igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
    end

    test "uses the first targets attribute that another dependency uses" do
      igniter =
        targets_install([
          ~s|{:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4}|,
          ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
          ~s|{:other, "~> 1.0", targets: @other_targets}|,
          ~s|{:vintage_net_ethernet, "~> 1.0"}|
        ])

      assert targets_mix_exs_after(igniter) =~
               ~s|{:vintage_net_ethernet, "~> 1.0", targets: @device_targets}|

      # Running it again changes nothing
      igniter
      |> apply_igniter!()
      |> Igniter.compose_task("vintage_net_ethernet.install", [])
      |> assert_unchanged("mix.exs")
    end

    test "works for dependencies that only have options" do
      igniter =
        targets_install([
          ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
          ~s|{:vintage_net_ethernet, path: "../vintage_net_ethernet"}|
        ])

      assert targets_mix_exs_after(igniter) =~
               ~s|{:vintage_net_ethernet, path: "../vintage_net_ethernet", targets: @device_targets}|
    end

    test "keeps the targets that the dependency already has" do
      targets_install([
        ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
        ~s|{:vintage_net_ethernet, "~> 1.0", targets: [:rpi0]}|
      ])
      |> assert_unchanged("mix.exs")
    end

    test "does nothing when no dependency uses a targets attribute" do
      targets_install([
        ~s|{:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4}|,
        ~s|{:vintage_net_ethernet, "~> 1.0"}|
      ])
      |> assert_unchanged("mix.exs")
    end

    test "falls back to @all_targets when it's defined but not used by a dependency" do
      mix_exs = """
      defmodule Test.MixProject do
        use Mix.Project

        @all_targets [:rpi4, :rpi5]

        def project do
          [app: :test, version: "0.1.0", deps: deps()]
        end

        defp deps do
          [
            {:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4},
            {:vintage_net_ethernet, "~> 1.0"}
          ]
        end
      end
      """

      igniter =
        test_project(files: %{"mix.exs" => mix_exs, "config/target.exs" => "import Config\n"})
        |> Igniter.compose_task("vintage_net_ethernet.install", [])

      assert targets_mix_exs_after(igniter) =~
               ~s|{:vintage_net_ethernet, "~> 1.0", targets: @all_targets}|
    end

    test "does nothing when the dependency isn't in mix.exs" do
      targets_install([~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|])
      |> assert_unchanged("mix.exs")
    end
  end
end
