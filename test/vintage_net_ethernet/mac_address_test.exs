# SPDX-FileCopyrightText: 2021 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetEthernet.MacAddressTest do
  use ExUnit.Case

  alias VintageNetEthernet.MacAddress

  describe "valid?/1" do
    test "good mac addresses" do
      assert MacAddress.valid?("01:23:45:67:89:AB")
      assert MacAddress.valid?("aA:bB:cC:dD:eE:fF")
    end

    test "bad mac addresses" do
      refute MacAddress.valid?("")
      refute MacAddress.valid?("192.168.1.1")
      refute MacAddress.valid?({1, 2, 3})
      refute MacAddress.valid?("g0:23:45:67:89:AB")
      refute MacAddress.valid?("01.23.45.67.89.AB")
    end
  end
end
