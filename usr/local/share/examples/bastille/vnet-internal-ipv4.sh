#!/bin/sh
#
# vnet-internal-ipv4.sh
#
# A sample script which runs bastille to create an internal,
# isolated virtual IPv4 network of VNET jails on a FreeBSD host.
#
# * core (Router forwarding packets between the site1 and site2)
# * r1 (Router for the site 1)
# * r2 (Router for the site 2)
# * h1 (Host on the site 1)
# * h2 (Host on the site 2)
#
# Routers (core, r1 and r2) are running RIPv2 to exchange routes.
#
#                              Site 1
#                    vri1_r1            vri1_h1
#        [Router(r1)]o ------ (vri1br) ------ o[Host (h1)]
#         vi1_r1 o  192.168.1.1     192.168.1.11
#    172.31.1.11 |
#                |
#             (vi1br)
#                |
#    172.31.1.1  |
#       vi1_core o
#           [Router(core)]
#       vi2_core o
#    172.31.2.1  |
#                |
#             (vi2br)
#                |
#    172.31.2.11 |
#         vi2_r2 o  192.168.2.1     192.168.2.11
#        [Router(r2)]o ------ (vri2br) ------ o[Host (h2)]
#                    vri2_nr2           vri2_h2
#                              Site 2
#

REL=12.1-RELEASE
bastille create -V core $REL \
    172.31.1.1/24@/vi1,172.31.2.1/24@/vi2 \
    router,routed_enable=YES,routed_flags="-P ripv2 -P no_rdisc"
bastille create -V r1 $REL \
    172.31.1.11/24@/vi1,192.168.1.1/24@/vri1 \
    router,routed_enable=YES,routed_flags="-P ripv2 -P no_rdisc"
bastille create -V r2 $REL \
    172.31.2.11/24@/vi2,192.168.2.1/24@/vri2 \
    router,routed_enable=YES,routed_flags="-P ripv2 -P no_rdisc"
bastille create -V h1 $REL \
    192.168.1.11/24@/vri1 \
    gw=192.168.1.1
bastille create -V h2 $REL \
    192.168.2.11/24@/vri2 \
    gw=192.168.2.1

