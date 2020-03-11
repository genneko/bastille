#!/bin/sh
#
# syntax-samples.sh
#
REL=12.1-RELEASE
#
# std1: a standard jail with an IP address, which will be set
#       on $bastille_jail_external or $basitlle_jail_loopback.
#
bastille create std1 $REL 127.1.1.1
#
# std2: a standard jail with two IP addresses.
#
bastille create std2 $REL 127.1.1.2,127.1.1.3
#
# std3: a standard jail with an IP address, which will be set
#       on bastille0.
#
bastille create std3 $REL 127.1.1.4@bastille0
#
# std4: a standard jail with an IP address, which will be added
#       to em0.
#
bastille create std4 $REL 192.168.131.132@em0
#
# vnet1: a VNET jail with an IP address on its own interface (em0_vnet1),
#        which will be connected to the bridge em0br,
#        to which the host's em0 is also connected.
#
bastille create -V vnet1 $REL 192.168.131.141/24@em0
#
# vnet2: a VNET jail with an IP address on its own interface (vi0_vnet2),
#        which will be connected to the bridge vi0br,
#        to which the host's virtual interface vi0 is also connected.
#        The host's vi0 will have 172.31.0.1 and it will be the default
#        gateway for the jail.
#
bastille create -V vnet2 $REL 172.31.0.11/24@/vi0=172.31.0.1 gw=172.31.0.1
#
# vnet3: a VNET jail with an IPv6 address on its own interface (vi0_vnet3),
#        which will be connected to the bridge vi0br,
#        to which the host's virtual interface vi0 is also connected.
#        The host's vi0 will have 2001:db8:10:31::1 and it will be the default
#        gateway for the jail.
#
bastille create -V vnet3 $REL 2001:db8:10:31::5/64@/vi0=2001:db8:10:31::1 gw=2001:db8:10:31::1
#
# vnet4: a VNET jail with two IPv4 and two IPv6 addresses on
#        its own interfaces (net0_vnet4 and net1_vnet4).
#        It will act as an IPv4/IPv6 dual-stack router and will run
#        RIPv2 and RIPng to exchange routes between other routers.
#        This jail has no connection to the host and external network.
#
bastille create -V vnet4 $REL 10.0.0.1/24@/net0,2001:db8:10:0::1/64@/net0,10.0.1.1/24@/net1,2001:db8:10:1::1/64@/net1 router,routed_enable=YES,routed_flags="-P ripv2 -P no_rdisc",route6d_enable=YES
#
# vnet5: a VNET jail with an IPv4 and an IPv6 addresses on its own
#        interface (net0_vnet5).
#        It gets routing information via RIPv2 and RIPng.
#        This jail has no connection to the host and external network.
#
bastille create -V vnet5 $REL 10.0.0.2/24@/net0,2001:db8:10:0::2/64@/net0 routed_enable=YES,routed_flags="-P ripv2 -P no_rdisc",route6d_enable=YES
#
# vnet6: a VNET jail with an IPv4 and an IPv6 addresses on its own
#        interface (net1_vnet6).
#        It gets routing information via RIPv2 and RIPng.
#        This jail has no connection to the host and external network.
#
bastille create -V vnet6 $REL 10.0.1.2/24@/net1,2001:db8:10:1::2/64@/net1 routed_enable=YES,routed_flags="-P ripv2 -P no_rdisc",route6d_enable=YES

