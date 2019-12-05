# 🍇 VintageNetEthernet

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

And then add the following to your `:vintage_net` configuration:

```elixir
  config :vintage_net, [
    config: [
      {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}
    ]
  ]
```
