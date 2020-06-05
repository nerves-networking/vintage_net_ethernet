defmodule VintageNetEthernet do
  @behaviour VintageNet.Technology

  alias VintageNet.Interface.RawConfig
  alias VintageNet.IP.{DhcpdConfig, IPv4Config}

  @moduledoc """
  Support for common wired Ethernet interface configurations

  Configurations for this technology are maps with a `:type` field set to
  `VintageNetEthernet`. The following additional fields are supported:

  * `:ipv4` - IPv4 options. See VintageNet.IP.IPv4Config.
  * `:dhcpd` - DHCP daemon options if running a static IP configuration. See
    VintageNet.IP.DhcpdConfig.

  An example DHCP configuration is:

  ```elixir
  %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}
  ```

  An example static IP configuration is:

  ```elixir
  %{
    type: VintageNetEthernet,
    ipv4: %{
      method: :static,
      address: {192, 168, 0, 5},
      prefix_length: 24,
      gateway: {192, 168, 0, 1}
    }
  }
  ```
  """

  @impl true
  def normalize(%{type: __MODULE__} = config) do
    config
    |> IPv4Config.normalize()
    |> DhcpdConfig.normalize()
  end

  @impl true
  def to_raw_config(ifname, %{type: __MODULE__} = config, opts) do
    normalized_config = normalize(config)

    %RawConfig{
      ifname: ifname,
      type: __MODULE__,
      source_config: normalized_config,
      required_ifnames: [ifname]
    }
    |> IPv4Config.add_config(normalized_config, opts)
    |> DhcpdConfig.add_config(normalized_config, opts)
  end

  @impl true
  def ioctl(_ifname, _command, _args) do
    {:error, :unsupported}
  end

  @impl true
  def check_system(_opts) do
    # TODO
    :ok
  end
end
