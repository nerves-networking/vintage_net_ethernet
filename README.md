# 🍇 VintageNetEthernet

[![Hex version](https://img.shields.io/hexpm/v/vintage_net_ethernet.svg "Hex version")](https://hex.pm/packages/vintage_net_ethernet)
[![API docs](https://img.shields.io/hexpm/v/vintage_net_ethernet.svg?label=hexdocs "API docs")](https://hexdocs.pm/vintage_net_ethernet/VintageNetEthernet.html)
[![CircleCI](https://circleci.com/gh/nerves-networking/vintage_net_ethernet.svg?style=svg)](https://circleci.com/gh/nerves-networking/vintage_net_ethernet)

`VintageNetEthernet` makes it easy to connect a device to a network over ethernet.

Assuming that your device supports ethernet hardware, all you need to do is add
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
      {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}},
    ]
  ]
```
