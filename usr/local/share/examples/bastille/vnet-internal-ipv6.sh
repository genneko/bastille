#!/bin/sh
#
# vnet-internal-ipv6.sh
#
# A sample script which runs bastille to create an internal,
# isolated virtual IPv6 network of VNET jails on a FreeBSD host.
#
# * core (Router forwarding packets between the site1 and site2)
# * r1 (Router for the site 1)
# * r2 (Router for the site 2)
# * h1 (Host on the site 1)
# * h2 (Host on the site 2)
#
# Routers (core, r1 and r2) are running RIPng to exchange routes.
# Host h1 has a static IPv6 address while h2 configures its IPv6
# address via SLAAC.
#
#                              Site 1
#                    vri1_r1            vri1_h1
#        [Router(r1)]o -------- (vri1br) -------- o[Host (h1)]
#         vi1_r1 o 2001:db8:1:1::1    2001:db8:1:1::11
# 2001:db8:1::11 |
#                |
#             (vi1br)
#                |
# 2001:db8:1::1  |
#       vi1_core o
#           [Router(core)]
#       vi2_core o
# 2001:db8:2::1  |
#                |
#             (vi2br)
#                |
# 2001:db8:2::11 |
#         vi2_r2 o 2001:db8:2:1::1    2001:db8:2:1::XXXX (SLAAC)
#        [Router(r2)]o -------- (vri2br) -------- o[Host (h2)]
#                    vri2_nr2           vri2_h2
#                              Site 2
#

REL=12.1-RELEASE
bastille create -V core $REL \
    2001:db8:1::1/64@/vi1,2001:db8:2::1/64@/vi2 \
    ipv6router,route6d_enable=YES
bastille create -V r1 $REL \
    2001:db8:1::11/64@/vi1,2001:db8:1:1::1/64@/vri1 \
    ipv6router,route6d_enable=YES
bastille create -V r2 $REL \
    2001:db8:2::11/64@/vi2,2001:db8:2:1::1/64@/vri2 \
    ipv6router,route6d_enable=YES,rtadvd_enable=YES,rtadvd_interfaces=vri2_r2
bastille create -V h1 $REL \
    2001:db8:1:1::11/64@/vri1 gw=2001:db8:1:1::1
bastille create -V h2 $REL \
    ::@/vri2

