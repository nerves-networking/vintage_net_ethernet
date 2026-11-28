# SPDX-FileCopyrightText: 2025 Jonatan Männchen
# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetEthernet.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Adds a wired Ethernet interface to your Nerves project's VintageNet configuration."
  end

  @spec example() :: String.t()
  def example() do
    "mix igniter.install vintage_net_ethernet"
  end

  @spec long_doc() :: String.t()
  def long_doc() do
    """
    #{short_doc()}

    This adds an Ethernet interface that gets its IP address using DHCP to the
    network interfaces in `config/target.exs`:

    ```elixir
    config :vintage_net,
      config: [
        {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}
      ]
    ```

    VintageNet's base configuration is added if the project doesn't have it. If
    the interface is already configured, it's left as it is. Other network
    interfaces aren't touched.

    If the project doesn't have a `config/target.exs`, the configuration is
    written to `config/config.exs`.

    ## Example

    ```bash
    #{example()}
    ```

    To use a static IP address instead of DHCP:

    ```bash
    mix igniter.install vintage_net_ethernet \\
      --ethernet-address 192.168.9.232/24 \\
      --ethernet-gateway 192.168.9.1 \\
      --ethernet-name-servers 1.1.1.1,8.8.8.8
    ```

    ## Options

    * `--ethernet-ifname` - The name of the Ethernet interface. Defaults to
      `eth0`.
    * `--ethernet-address` - A static IPv4 address for the interface. Either
      append the prefix length like `192.168.9.232/24` or pass
      `--ethernet-netmask`. DHCP is used when this isn't specified.
    * `--ethernet-netmask` - The subnet mask for the static IPv4 address. E.g.,
      `255.255.255.0`. It's written to the configuration as a `:prefix_length`.
    * `--ethernet-gateway` - The IPv4 address of the default gateway when using
      a static IPv4 address.
    * `--ethernet-name-servers` - A comma-separated list of name server IP
      addresses to use with a static IPv4 address.

    See the `VintageNetEthernet` documentation for everything else that can be
    configured, like setting the MAC address.
    """
  end
end

if Code.ensure_loaded?(Igniter) and Code.ensure_loaded?(VintageNet.Generator) do
  defmodule Mix.Tasks.VintageNetEthernet.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias VintageNet.Generator

    @default_ifname "eth0"
    @static_options [
      :ethernet_address,
      :ethernet_netmask,
      :ethernet_gateway,
      :ethernet_name_servers
    ]

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :vintage_net_ethernet,
        example: __MODULE__.Docs.example(),
        schema: [
          ethernet_ifname: :string,
          ethernet_address: :string,
          ethernet_netmask: :string,
          ethernet_gateway: :string,
          ethernet_name_servers: :string
        ],
        defaults: [ethernet_ifname: @default_ifname]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      ifname = options[:ethernet_ifname] || @default_ifname

      with :ok <- validate_ifname(ifname),
           {:ok, ipv4} <- ipv4_config(options) do
        config = interface_config(ipv4)

        igniter
        |> restrict_dep_to_targets()
        |> maybe_add_kept_notice(ifname, config, ipv4)
        |> Generator.add_interface(ifname, {:code, config})
        |> maybe_add_not_nerves_notice()
      else
        {:error, message} ->
          Igniter.add_issue(igniter, "vintage_net_ethernet: " <> message)
      end
    end

    # Keeps vintage_net_ethernet off the host when the project restricts other
    # dependencies to its targets. See VintageNet.Generator.
    defp restrict_dep_to_targets(igniter) do
      Generator.restrict_dep_to_targets(igniter, :vintage_net_ethernet)
    end

    # Linux limits interface names to 15 bytes and doesn't allow whitespace or
    # slashes in them.
    defp validate_ifname(ifname) do
      if ifname =~ ~r/\A[^\s\/]{1,15}\z/ and ifname not in [".", ".."] do
        :ok
      else
        {:error,
         """
         invalid --ethernet-ifname #{inspect(ifname)}.

         Pass the name of a network interface like eth0 or end0.
         """}
      end
    end

    defp ipv4_config(options) do
      if Enum.any?(@static_options, &options[&1]) do
        static_ipv4_config(options)
      else
        {:ok, [method: :dhcp]}
      end
    end

    defp static_ipv4_config(options) do
      with {:ok, address, prefix_length} <- parse_address(options[:ethernet_address]),
           {:ok, prefix_length} <- parse_netmask(options[:ethernet_netmask], prefix_length),
           {:ok, gateway} <- parse_gateway(options[:ethernet_gateway]),
           {:ok, name_servers} <- parse_name_servers(options[:ethernet_name_servers]) do
        {:ok,
         [method: :static, address: address, prefix_length: prefix_length] ++
           gateway ++ name_servers}
      end
    end

    defp parse_address(nil) do
      {:error,
       """
       --ethernet-address is required when using --ethernet-netmask,
       --ethernet-gateway or --ethernet-name-servers.

       Those options are for static IPv4 configurations. Pass the address like
       this: --ethernet-address 192.168.9.232/24
       """}
    end

    defp parse_address(value) do
      case String.split(value, "/") do
        [address] ->
          if ipv4?(address), do: {:ok, address, nil}, else: invalid_address(value)

        [address, prefix_length] ->
          with true <- ipv4?(address),
               {bits, ""} when bits in 0..32 <- Integer.parse(prefix_length) do
            {:ok, address, bits}
          else
            _ -> invalid_address(value)
          end

        _ ->
          invalid_address(value)
      end
    end

    defp invalid_address(value) do
      {:error,
       """
       invalid --ethernet-address #{inspect(value)}.

       Pass an IPv4 address with an optional prefix length. For example,
       192.168.9.232/24 or 192.168.9.232 together with --ethernet-netmask.
       """}
    end

    defp parse_netmask(nil, nil) do
      {:error,
       """
       the subnet for --ethernet-address is missing.

       Either append the prefix length to the address like 192.168.9.232/24 or
       pass --ethernet-netmask 255.255.255.0.
       """}
    end

    defp parse_netmask(nil, prefix_length), do: {:ok, prefix_length}

    defp parse_netmask(netmask, nil) do
      with {:ok, tuple} <- parse_ipv4(netmask),
           {:ok, prefix_length} <- VintageNet.IP.subnet_mask_to_prefix_length(tuple) do
        {:ok, prefix_length}
      else
        _ ->
          {:error,
           """
           invalid --ethernet-netmask #{inspect(netmask)}.

           Pass an IPv4 subnet mask like 255.255.255.0.
           """}
      end
    end

    defp parse_netmask(_netmask, _prefix_length) do
      {:error,
       """
       --ethernet-netmask can't be used when --ethernet-address has a prefix
       length. Pass one or the other.
       """}
    end

    defp parse_gateway(nil), do: {:ok, []}

    defp parse_gateway(gateway) do
      if ipv4?(gateway) do
        {:ok, [gateway: gateway]}
      else
        {:error,
         """
         invalid --ethernet-gateway #{inspect(gateway)}.

         Pass the IPv4 address of the default gateway. For example, 192.168.9.1.
         """}
      end
    end

    defp parse_name_servers(nil), do: {:ok, []}

    defp parse_name_servers(value) do
      name_servers = value |> String.split(",") |> Enum.map(&String.trim/1)

      if Enum.all?(name_servers, &ip?/1) do
        {:ok, [name_servers: name_servers]}
      else
        {:error,
         """
         invalid --ethernet-name-servers #{inspect(value)}.

         Pass a comma-separated list of IP addresses. For example, 1.1.1.1,8.8.8.8.
         """}
      end
    end

    defp ipv4?(string), do: match?({:ok, _}, parse_ipv4(string))

    defp parse_ipv4(string),
      do: string |> String.to_charlist() |> :inet.parse_ipv4strict_address()

    defp ip?(string) do
      match?({:ok, _}, string |> String.to_charlist() |> :inet.parse_strict_address())
    end

    # The configuration is built as source code so that the keys are written in
    # the same order as in the documentation.
    defp interface_config(ipv4) do
      pairs = Enum.map_join(ipv4, ", ", fn {key, value} -> "#{key}: #{inspect(value)}" end)

      Sourceror.parse_string!("%{type: VintageNetEthernet, ipv4: %{#{pairs}}}")
    end

    # `VintageNet.Generator.add_interface/3` never changes an interface that's
    # already configured. That's what's wanted, but when a static IP address was
    # asked for and it's not what ends up in the configuration, the user needs
    # to know.
    defp maybe_add_kept_notice(igniter, ifname, config, ipv4) do
      with :static <- ipv4[:method],
           {:ok, existing} <- existing_interface_config(igniter, ifname),
           false <- same_code?(existing, config) do
        Igniter.add_notice(igniter, """
        vintage_net_ethernet: #{inspect(ifname)} is already configured in config/#{Generator.config_file(igniter)},
        so it was left as it is. To use the static IP address, update its
        configuration to:

            #{Sourceror.to_string(config)}
        """)
      else
        _ -> igniter
      end
    end

    # The update callback of `VintageNet.Generator.configure_interface/5` is
    # the supported way of getting to an interface's existing configuration, so
    # this does a trial run and throws the result away.
    defp existing_interface_config(igniter, ifname) do
      ref = make_ref()

      _ =
        Generator.configure_interface(igniter, ifname, VintageNetEthernet, [], fn zipper ->
          send(self(), {ref, Sourceror.Zipper.node(zipper)})
          {:ok, zipper}
        end)

      receive do
        {^ref, existing} -> {:ok, existing}
      after
        0 -> :error
      end
    end

    defp same_code?(a, b), do: strip_meta(a) == strip_meta(b)

    defp strip_meta(quoted) do
      quoted
      |> Sourceror.to_string()
      |> Code.string_to_quoted!()
      |> Macro.prewalk(&Macro.update_meta(&1, fn _meta -> [] end))
    end

    defp maybe_add_not_nerves_notice(igniter) do
      if Generator.config_file(igniter) == "target.exs" do
        igniter
      else
        Igniter.add_notice(igniter, """
        vintage_net_ethernet: config/target.exs was not found, so the Ethernet
        interface was added to config/config.exs.

        VintageNet is meant for Nerves devices and these defaults assume a
        Nerves project. If this project also runs on your computer, move the
        configuration to where it only applies to the device.
        """)
      end
    end
  end
else
  defmodule Mix.Tasks.VintageNetEthernet.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      if Code.ensure_loaded?(Igniter) do
        Mix.shell().error("""
        The task 'vintage_net_ethernet.install' requires a version of vintage_net that has
        `VintageNet.Generator`. Please update vintage_net and try again.

        If vintage_net was compiled before igniter was added to the project, run
        `mix deps.compile vintage_net --force`.
        """)
      else
        Mix.shell().error("""
        The task 'vintage_net_ethernet.install' requires igniter. Please install igniter and try again.

        For more information, see: https://igniter.hexdocs.pm/readme.html#installation
        """)
      end

      exit({:shutdown, 1})
    end
  end
end
