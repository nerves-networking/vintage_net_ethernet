# SPDX-FileCopyrightText: 2021 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetEthernet.CookbookTest do
  use ExUnit.Case

  alias VintageNetEthernet.Cookbook

  test "dynamic_ipv4/0" do
    assert {:ok,
            %{
              type: VintageNetEthernet,
              ipv4: %{method: :dhcp}
            }} == Cookbook.dynamic_ipv4()
  end
end
