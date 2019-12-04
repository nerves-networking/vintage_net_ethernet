defmodule VintageNet.Technology.Ethernet do
  @behaviour VintageNet.Technology

  @moduledoc """
  Deprecated - Use VintageNetEthernet now

  This module will automatically redirect your configurations to VintageNetEthernet so
  no changes are needed to your code. New code should use the new module.
  """
  @impl true
  def normalize(%{type: __MODULE__} = config) do
    config
    |> update_config()
    |> VintageNetEthernet.normalize()
  end

  @impl true
  def to_raw_config(ifname, config, opts) do
    updated_config = update_config(config)
    VintageNetEthernet.to_raw_config(ifname, updated_config, opts)
  end

  defp update_config(config) do
    Map.put(config, :type, VintageNetEthernet)
  end

  defdelegate ioctl(ifname, command, args), to: VintageNetEthernet

  defdelegate check_system(opts), to: VintageNetEthernet
end
