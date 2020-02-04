![vintage net logo](assets/logo.png)

[![Hex version](https://img.shields.io/hexpm/v/vintage_net_ethernet.svg "Hex version")](https://hex.pm/packages/vintage_net_ethernet)
[![API docs](https://img.shields.io/hexpm/v/vintage_net_ethernet.svg?label=hexdocs "API docs")](https://hexdocs.pm/vintage_net_ethernet/VintageNetEthernet.html)
[![CircleCI](https://circleci.com/gh/nerves-networking/vintage_net_ethernet.svg?style=svg)](https://circleci.com/gh/nerves-networking/vintage_net_ethernet)
[![Coverage Status](https://coveralls.io/repos/github/nerves-networking/vintage_net_ethernet/badge.svg?branch=master)](https://coveralls.io/github/nerves-networking/vintage_net_ethernet?branch=master)

`VintageNetEthernet` adds support to `VintageNet` for wired Ethernet
connections. It can be used for virtual Ethernet or for other non-wired Ethernet
scenarios, but support is minimal. You may also be interested in
[`VintageNetDirect`](https://github.com/nerves-networking/vintage_net_direct) or
[`VintageNetWiFi`](https://github.com/nerves-networking/vintage_net_direct).

Assuming that your device has Ethernet ports, all you need to do is add
`:vintage_net_ethernet` to your `mix` dependencies like this:

```elixir
def deps do
  [
    {:vintage_net_ethernet, "~> 0.7.0", targets: @all_targets}
  ]
end
```

## Using

Wired Ethernet interfaces typically have names like `"eth0"`, `"eth1"`, etc.
when using Nerves.

An example configuration for enabling an Ethernet interface that dynamically
gets an IP address is:

```elixir
config :vintage_net,
  config: [
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{
         method: :dhcp
       }
     }}
  ]
```

You can also set the configuration at runtime:

```elixir
iex> VintageNet.configure("eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}})
:ok
```

Here's a static IP configuration:

```elixir
iex> VintageNet.configure("eth0", %{
    type: VintageNetEthernet,
    ipv4: %{
      method: :static,
      address: "192.168.9.232",
      prefix_length: 24,
      gateway: "192.168.9.1",
      name_servers: ["1.1.1.1"]
    }
  })
:ok
```

In the above, IP addresses were passed as strings for convenience, but it's also
possible to pass tuples like `{192, 168, 9, 232}` as is more typical in Elixir
and Erlang. VintageNet internally works with tuples.

The following fields are supported:

* `:method` - Set to `:dhcp`, `:static`, or `:disabled`. If `:static`, then at
  least an IP address and mask need to be set. `:disabled` enables the interface
  and doesn't apply an IP configuration
* `:address` - the IP address for static IP addresses
* `:prefix_length` - the number of bits in the IP address to use for the subnet
  (e.g., 24)
* `:netmask` - either this or `prefix_length` is used to determine the subnet.
* `:gateway` - the default gateway for this interface (optional)
* `:name_servers` - a list of name servers for static configurations (optional)
* `:domain` - a search domain for DNS

Wired Ethernet connections are monitored for Internet connectivity if a default
gateway is available. When internet-connected, they are preferred over all other
network technologies even when the others provide default gateways.

## Properties

There are no wired Ethernet-specific properties. See `vintage_net` for the
default set of properties for all interface types.
