# SPDX-FileCopyrightText: 2019 Frank Hunleth
# SPDX-FileCopyrightText: 2019 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetEthernet do
  @moduledoc """
  Support for common wired Ethernet interface configurations

  Configurations for this technology are maps with a `:type` field set to
  `VintageNetEthernet`. The following additional fields are supported:

  * `:ipv4` - IPv4 options. See VintageNet.IP.IPv4Config.
  * `:dhcpd` - DHCP daemon options if running a static IP configuration. See
    VintageNet.IP.DhcpdConfig.
  * `:mac_address` - A MAC address string or an MFArgs tuple. VintageNet will
    set the MAC address of the network interface to the value specified. If an
    MFArgs tuple is passed, VintageNet will `apply` it and use the return value
    as the address.
  * `:vintage_net_ethernet` - `wpa_supplicant` options for wired IEEE 802.1X
    or MACsec. When present, a `wpa_supplicant` is run on the interface using
    the `wired` driver. Either pass `wpa_supplicant` network options or
    pass the contents of a `wpa_supplicant.conf` as `:wpa_supplicant_conf`. This
    requires adding `:vintage_net_supplicant` to your dependencies.
  * `:verbose` - Set to `true` to enable verbose `wpa_supplicant` logging

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

  The supported `wpa_supplicant` network options are `:key_mgmt`
  (`:IEEE8021X` or `:none`), the EAP options (`:eap`, `:identity`,
  `:anonymous_identity`, `:password`, `:phase1`, `:phase2`, `:eapol_flags`,
  `:fragment_size`, `:ocsp`, `:openssl_ciphers`, `:erp`,
  `:domain_suffix_match`), the certificate and key options (`:ca_cert`,
  `:client_cert`, `:private_key`, `:private_key_passwd`, `:dh_file`, their
  phase 2 versions ending in `2`, `:pin` and `:pac_file`), and the MACsec
  options (`:macsec_policy`, `:macsec_integ_only`, `:macsec_replay_protect`,
  `:macsec_replay_window`, `:macsec_port`, `:mka_cak`, `:mka_ckn`,
  `:mka_priority`). See the `wpa_supplicant.conf` documentation for what they
  do. Other options are ignored.

  When the private key is in an HSM, set `:pkcs11_engine_path` to the OpenSSL
  PKCS #11 engine and `:pkcs11_module_path` to the PKCS #11 module for the
  HSM, and pass a PKCS #11 URI as the `:private_key`. `wpa_supplicant` is a
  separate OS process, so an engine that's loaded in the Erlang VM isn't
  available to it.

  An example IEEE 802.1X configuration is:

  ```elixir
  %{
    type: VintageNetEthernet,
    vintage_net_ethernet: %{
      key_mgmt: :IEEE8021X,
      eap: "PEAP",
      identity: "user",
      password: "password",
      phase2: "auth=MSCHAPV2"
    },
    ipv4: %{method: :dhcp}
  }
  ```

  An example EAP-TLS configuration with the private key in an HSM is:

  ```elixir
  %{
    type: VintageNetEthernet,
    vintage_net_ethernet: %{
      pkcs11_engine_path: "/usr/lib/engines-3/libpkcs11.so",
      pkcs11_module_path: "/path/to/pkcs11_module.so",
      key_mgmt: :IEEE8021X,
      eap: "TLS",
      identity: "host/device.example.com",
      ca_cert: "/data/radius_ca.pem",
      domain_suffix_match: "radius.example.com",
      client_cert: "/data/device_cert.pem",
      private_key: "pkcs11:token=0"
    },
    ipv4: %{method: :dhcp}
  }
  ```
  """
  @behaviour VintageNet.Technology

  alias VintageNet.Interface.RawConfig
  alias VintageNet.IP.{DhcpdConfig, IPv4Config}
  alias VintageNetEthernet.Cookbook
  alias VintageNetEthernet.MacAddress
  alias VintageNetSupplicant.WPASupplicant

  require Logger

  @impl VintageNet.Technology
  def normalize(%{type: __MODULE__} = config) do
    config
    |> normalize_ethernet()
    |> normalize_mac_address()
    |> IPv4Config.normalize()
    |> DhcpdConfig.normalize()
  end

  defp normalize_ethernet(%{vintage_net_ethernet: %{wpa_supplicant_conf: conf}} = config) do
    check_supplicant!()
    %{config | vintage_net_ethernet: %{wpa_supplicant_conf: conf}}
  end

  defp normalize_ethernet(%{vintage_net_ethernet: _ethernet} = config) do
    check_supplicant!()
    config
  end

  defp normalize_ethernet(config) do
    config
  end

  # vintage_net_supplicant is an optional dependency
  defp check_supplicant!() do
    if not Code.ensure_loaded?(WPASupplicant) do
      raise ArgumentError,
            "The :vintage_net_ethernet options require :vintage_net_supplicant. Add it to your dependencies."
    end
  end

  defp normalize_mac_address(%{mac_address: mac_address} = config) do
    if MacAddress.valid?(mac_address) or mfargs?(mac_address) do
      config
    else
      raise ArgumentError, "Invalid MAC address #{inspect(mac_address)}"
    end
  end

  defp normalize_mac_address(config), do: config

  defp mfargs?({m, f, a}) when is_atom(m) and is_atom(f) and is_list(a), do: true
  defp mfargs?(_), do: false

  @impl VintageNet.Technology
  def to_raw_config(ifname, %{type: __MODULE__} = config, opts) do
    normalized_config = normalize(config)

    %RawConfig{
      ifname: ifname,
      type: __MODULE__,
      source_config: normalized_config,
      required_ifnames: [ifname]
    }
    |> add_supplicant_config(normalized_config, opts)
    |> add_mac_address_config(normalized_config)
    |> IPv4Config.add_config(normalized_config, opts)
    |> DhcpdConfig.add_config(normalized_config, opts)
  end

  # Only run a wpa_supplicant when asked for
  defp add_supplicant_config(raw_config, %{vintage_net_ethernet: ethernet} = config, opts) do
    ifname = raw_config.ifname
    tmpdir = Keyword.fetch!(opts, :tmpdir)

    wpa_supplicant_conf_path = Path.join(tmpdir, "wpa_supplicant.conf.#{ifname}")
    control_interface_dir = Path.join(tmpdir, "wpa_supplicant")
    verbose = Map.get(config, :verbose, false)

    files = [
      {wpa_supplicant_conf_path, ethernet_to_supplicant_contents(ethernet, control_interface_dir)}
    ]

    wpa_supplicant_options = [
      wpa_supplicant: "wpa_supplicant",
      ifname: ifname,
      driver: "wired",
      wpa_supplicant_conf_path: wpa_supplicant_conf_path,
      control_path: control_interface_dir,
      verbose: verbose
    ]

    %{
      raw_config
      | files: raw_config.files ++ files,
        cleanup_files: raw_config.cleanup_files ++ [Path.join(control_interface_dir, ifname)],
        restart_strategy: :rest_for_one,
        child_specs: raw_config.child_specs ++ [{WPASupplicant, wpa_supplicant_options}]
    }
  end

  defp add_supplicant_config(raw_config, _config, _opts), do: raw_config

  defp ethernet_to_supplicant_contents(
         %{wpa_supplicant_conf: conf},
         control_interface_dir
       ) do
    [into_newlines(["ctrl_interface=#{control_interface_dir}"]), conf]
    |> IO.chardata_to_string()
  end

  defp ethernet_to_supplicant_contents(ethernet, control_interface_dir) do
    config = [
      "ctrl_interface=#{control_interface_dir}"
      | options_config(global_options(), ethernet)
    ]

    iodata = [into_newlines(config), into_ethernet_network_config(ethernet)]
    IO.chardata_to_string(iodata)
  end

  # wpa_supplicant options that go outside of the network block. These are
  # written as is since wpa_supplicant doesn't unquote them.
  defp global_options() do
    [
      # Where to find the OpenSSL PKCS #11 engine and the PKCS #11 module when
      # the private key is in an HSM
      pkcs11_engine_path: :raw,
      pkcs11_module_path: :raw
    ]
  end

  # wpa_supplicant network options that make sense on a wired interface in
  # the order that they're written. Strings get quoted and escaped. Everything
  # else is written as is.
  defp network_options() do
    [
      # EAP settings
      eap: :raw,
      identity: :string,
      anonymous_identity: :string,
      password: :string,
      phase1: :string,
      phase2: :string,
      eapol_flags: :raw,
      fragment_size: :raw,
      ocsp: :raw,
      openssl_ciphers: :string,
      erp: :raw,
      domain_suffix_match: :string,

      # Certificates and keys. These are paths or blob references.
      ca_cert: :string,
      ca_cert2: :string,
      dh_file: :string,
      dh_file2: :string,
      client_cert: :string,
      client_cert2: :string,
      private_key: :string,
      private_key2: :string,
      private_key_passwd: :string,
      private_key2_passwd: :string,
      pin: :string,
      pac_file: :string,

      # MACsec settings
      macsec_policy: :raw,
      macsec_integ_only: :raw,
      macsec_replay_protect: :raw,
      macsec_replay_window: :raw,
      macsec_port: :raw,
      mka_cak: :raw,
      mka_ckn: :raw,
      mka_priority: :raw
    ]
  end

  defp into_ethernet_network_config(ethernet) do
    network_config([key_mgmt_config(ethernet) | options_config(network_options(), ethernet)])
  end

  defp options_config(options, ethernet) do
    for {key, type} <- options, value = ethernet[key], value != nil do
      "#{key}=#{option_value(type, value)}"
    end
  end

  defp key_mgmt_config(%{key_mgmt: key_mgmt}) do
    "key_mgmt=#{key_mgmt |> List.wrap() |> Enum.map_join(" ", &key_mgmt_to_string/1)}"
  end

  defp key_mgmt_config(_ethernet), do: nil

  defp key_mgmt_to_string(:IEEE8021X), do: "IEEE8021X"
  defp key_mgmt_to_string(:none), do: "NONE"

  defp option_value(:string, value), do: escape_string(value)
  defp option_value(:raw, value), do: to_string(value)

  defp network_config(config) do
    ["network={", "\n", into_newlines(config), "}", "\n"]
  end

  defp escape_string(value) when is_binary(value) do
    # Use inspect since the Elixir API that escapes non-printable characters is
    # currently private.
    inspect(value, binaries: :as_strings)
  end

  defp into_newlines(config) do
    Enum.map(config, fn
      nil -> []
      conf -> [conf, "\n"]
    end)
  end

  defp add_mac_address_config(raw_config, %{mac_address: mac_address}) do
    resolved_mac = resolve_mac(mac_address)

    if MacAddress.valid?(resolved_mac) do
      new_up_cmds =
        raw_config.up_cmds ++
          [{:run, "ip", ["link", "set", raw_config.ifname, "address", resolved_mac]}]

      %{raw_config | up_cmds: new_up_cmds}
    else
      Logger.warning(
        "vintage_net_ethernet: ignoring invalid MAC address '#{inspect(resolved_mac)}'"
      )

      raw_config
    end
  end

  defp add_mac_address_config(raw_config, _config) do
    raw_config
  end

  defp resolve_mac({m, f, args}) do
    apply(m, f, args)
  rescue
    e -> {:error, e}
  end

  defp resolve_mac(mac_address), do: mac_address

  @impl VintageNet.Technology
  def ioctl(_ifname, _command, _args) do
    {:error, :unsupported}
  end

  @impl VintageNet.Technology
  def check_system(_opts) do
    # TODO
    :ok
  end

  @spec quick_configure(VintageNet.ifname()) :: :ok | {:error, term()}
  def quick_configure(ifname \\ "eth0") do
    with {:ok, config} <- Cookbook.dynamic_ipv4() do
      VintageNet.configure(ifname, config)
    end
  end
end
