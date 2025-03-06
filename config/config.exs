# SPDX-FileCopyrightText: 2019 Jon Carstens
# SPDX-FileCopyrightText: 2020 Matt Ludwigs
# SPDX-FileCopyrightText: 2022 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
import Config

# Overrides for unit tests:
#
# * udhcpc_handler: capture whatever happens with udhcpc
# * resolvconf: don't update the real resolv.conf
# * persistence_dir: use the current directory
config :vintage_net,
  udhcpc_handler: VintageNetTest.CapturingUdhcpcHandler,
  resolvconf: "/dev/null",
  persistence_dir: "./test_tmp/persistence",
  path: "#{File.cwd!()}/test/fixtures/root/bin"
