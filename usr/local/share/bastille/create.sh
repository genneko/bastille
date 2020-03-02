#!/bin/sh
# 
# Copyright (c) 2018-2020, Christer Edwards <christer.edwards@gmail.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

. /usr/local/share/bastille/colors.pre.sh
. /usr/local/etc/bastille/bastille.conf

usage() {
    echo -e "${COLOR_RED}Usage: bastille create [option] name release ip [rc.conf options].\n" \
            "       [option]\n" \
            "       -V|--vnet|vnet: VNET jail\n" \
            "       -T|--thick|thick: Thick jail\n" \
            "\n" \
            "       [ip] comma-separated list of the following syntaxes\n" \
            "            (addresses can be either IPv4 or IPv6)\n" \
            "       10.0.0.5: an IP for a standard jail on the default I/F\n" \
            "       10.0.0.5@em0: an IP for a standard jail on a specified I/F\n" \
            "       10.0.0.5/24@em0: an IP for a VNET jail bridged to a specified I/F\n" \
            "       10.0.0.5/24@/vi0=10.0.0.1: an IP for a VNET jail and a virtual I/F\n" \
            "       10.0.0.5/24@/net0: an IP for a VNET jail on an internal bridged network\n" \
            "\n" \
            "       [rc.conf options] comma-separated list of the following syntaxes\n" \
            "       gw=A.B.C.D|gw=X:X::X:X: default gateways\n" \
            "       router: IPv4/IPv6 router (forwarding IPv4/IPv6)\n" \
            "       ipv4router: IPv4 router (forwarding IPv4)\n" \
            "       ipv6router: IPv6 router (forwarding IPv6)\n" \
            "       key=value: arbitrary rc.conf variable and its value\n\n" \
            "${COLOR_RESET}"
    exit 1
}

running_jail() {
    if [ -n "$(jls name | awk "/^${NAME}$/")" ]; then
        echo -e "${COLOR_RED}A running jail matches name.${COLOR_RESET}"
        exit 1
    elif [ -d "${bastille_jailsdir}/${NAME}" ]; then
        echo -e "${COLOR_RED}Jail: ${NAME} already created.${COLOR_RESET}"
        exit 1
    fi
}

validate_all_ip() {
    local ip iplist addr iface ifaddr
    iplist=$1

    while [ ${#iplist} -gt 0 ]; do
        case "${iplist}" in
            *,*)
                ip=${iplist%%,*}
                iplist=${iplist#*,}
                ;;
            *)
                ip=$iplist
                iplist=""
                ;;
        esac

        case "${ip}" in
            *@*)
                addr="${ip%%@*}"
                iface="${ip#*@}"
                case "${iface}" in
                    *=*)
                        ifaddr="${iface#*=}"
                        iface="${iface%%=*}"
                        ;;
                    *)
                        ifaddr=""
                        ;;
                esac
                ;;
            *)
                addr=$ip
                iface=""
                ifaddr=""
                ;;
        esac

        validate_netif $addr $iface $ifaddr
    done
}

is_ip6() {
    local addr=$1
    echo "${addr}" | grep -qE '^(([a-fA-F0-9:]+$)|([a-fA-F0-9:]+\/[0-9]{1,3}$))' > /dev/null 2>&1
}

validate_ip() {
    local addr=$1
    local iface=$2
    IP6_MODE="disable"
    if is_ip6 "$addr"; then
        echo -e "${COLOR_GREEN}Valid: (${addr}).${COLOR_RESET}"
        IP6_ADDR="${IP6_ADDR:+${IP6_ADDR}\n}  ip6.addr ${IP6_ADDR:++}= \"${iface:+$iface|}$addr\";"
        IP6_MODE="new"
        IP_AF=6
    else
        local IFS
        if echo "${addr}" | grep -Eq '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))?$'; then
            TEST_IP=$(echo "${addr}" | cut -d / -f1)
            IFS=.
            set ${TEST_IP}
            for quad in 1 2 3 4; do
                if eval [ \$$quad -gt 255 ]; then
                    echo "Invalid: (${TEST_IP})"
                    exit 1
                fi
            done
            if ifconfig | grep -qw "${TEST_IP}"; then
                echo -e "${COLOR_YELLOW}Warning: ip address already in use (${TEST_IP}).${COLOR_RESET}"
            else
                echo -e "${COLOR_GREEN}Valid: (${addr}).${COLOR_RESET}"
            fi
            IP4_ADDR="${IP4_ADDR:+${IP4_ADDR}\n}  ip4.addr ${IP4_ADDR:++}= \"${iface:+$iface|}$addr\";"
            IP_AF=4
        else
            echo -e "${COLOR_RED}Invalid: (${addr}).${COLOR_RESET}"
            exit 1
        fi
    fi
}

validate_netif() {
    local addr=$1
    local iface=$2
    local ifaddr=$3
    local masklen
    if [ -z "$iface" ] && [ -z "${VNET_JAIL}" ]; then
        if [ -z "${bastille_jail_loopback}" ] && [ -n "${bastille_jail_external}" ]; then
            iface=${bastille_jail_external}
        elif [ -n "${bastille_jail_loopback}" ] && [ -z "${bastille_jail_external}" ]; then
            iface=${bastille_jail_interface}
        fi
        validate_ip $addr $iface
        return
    fi
    validate_ip $addr $iface
    local LIST_INTERFACES=$(ifconfig -l)
    if echo "${LIST_INTERFACES} VNET" | grep -qwo "${iface}"; then
        if [ -n "${VNET_JAIL}" ]; then
            echo -e "${COLOR_GREEN}Valid: (Bridged to ${iface}).${COLOR_RESET}"
            VNET_ISOLATED=""
            VNET_PRESTART="${VNET_PRESTART:+${VNET_PRESTART}\n}  exec.prestart += \"${bastille_sharedir}/vnet add ${iface} ${iface}_${NAME}\";";
        else
            echo -e "${COLOR_GREEN}Valid: (${iface}).${COLOR_RESET}"
            IFLIST="${IFLIST:+${IFLIST}\n}${iface}";
        fi
    elif [ -z "${VNET_JAIL}" ]; then
        echo -e "${COLOR_RED}Invalid: (No such interface ${iface}).${COLOR_RESET}"
        exit 1
    else
        if [ -z "${iface}" ]; then
            echo -e "${COLOR_RED}Specify an interface for the VNET jail address $addr.${COLOR_RESET}"
            exit 1
        fi
        VNET_VIRTIF="1"
        if echo "$iface" | grep -Eq '^/.+' > /dev/null 2>&1; then
            iface="${iface#/}"
            if [ -z "$ifaddr" ]; then
                echo -e "${COLOR_GREEN}Valid: (Connected to an internal bridge ${iface}br).${COLOR_RESET}"
                VNET_PRESTART="${VNET_PRESTART:+${VNET_PRESTART}\n}  exec.prestart += \"${bastille_sharedir}/vnet add -b ${iface} ${iface}_${NAME}\";";

            else
                echo -e "${COLOR_GREEN}Valid: (a virtual interface ${iface}(${ifaddr})).${COLOR_RESET}"
                VNET_ISOLATED=""
                masklen=${addr##*/}
                if [ -z "${ifaddr}" ]; then
                    echo -e "${COLOR_RED}Specify a gateway (to be assgined to ${iface}).${COLOR_RESET}"
                    exit 1
                elif [ -z "${masklen}" ]; then
                    echo -e "${COLOR_RED}Specify a masklen for the IP address $IP (to be assgined to ${iface}).${COLOR_RESET}"
                    exit 1
                elif [ "${IP_AF}" == "4" ]; then
                    if [ "${masklen}" -le 0 -o "${masklen}" -ge 32 ]; then
                        echo -e "${COLOR_RED}Invalid: 0 < masklen < 32 for the IPv4 address $IP (to be assgined to ${iface}).${COLOR_RESET}"
                        exit 1
                    else
                        VNET_PRESTART="${VNET_PRESTART:+${VNET_PRESTART}\n}  exec.prestart += \"${bastille_sharedir}/vnet add -4 $ifaddr/$masklen ${iface} ${iface}_${NAME}\";";
                    fi
                elif [ "${IP_AF}" == "6" ]; then
                    if [ "${masklen}" -ne 64 ]; then
                        echo -e "${COLOR_RED}Invalid: Specify /64 for the IPv6 address $IP (to be assgined to ${iface}).${COLOR_RESET}"
                        exit 1
                    else
                        VNET_PRESTART="${VNET_PRESTART:+${VNET_PRESTART}\n}  exec.prestart += \"${bastille_sharedir}/vnet add -6 $ifaddr/$masklen ${iface} ${iface}_${NAME}\";";
                    fi
                fi
            fi
        fi
    fi

    if [ -n "${VNET_JAIL}" ]; then
        if [ "${IP_AF}" == "4" ]; then
            if [ "${addr}" == "0.0.0.0" ]; then
                RC_CONF="${RC_CONF:+${RC_CONF}\n}ifconfig_${iface}_${NAME}=\"SYNCDHCP\""
            else
                RC_CONF="${RC_CONF:+${RC_CONF}\n}ifconfig_${iface}_${NAME}=\"inet $addr\""
            fi
        elif [ "${IP_AF}" == "6" ]; then
            if echo "${addr}" | grep -Eq '^[0:]+$' > /dev/null 2>&1; then
                RC_CONF="${RC_CONF:+${RC_CONF}\n}ifconfig_${iface}_${NAME}_ipv6=\"inet6 accept_rtadv\""
            else
                RC_CONF="${RC_CONF:+${RC_CONF}\n}ifconfig_${iface}_${NAME}_ipv6=\"inet6 $addr\""
            fi
        fi

        IFLIST="${IFLIST:+${IFLIST}\n}${iface}_${NAME}";
        VNET_PRESTOP="${VNET_PRESTOP:+${VNET_PRESTOP}\n}  exec.prestop  += \"ifconfig ${iface}_${NAME} -vnet ${NAME}\";";
        VNET_POSTSTOP="${VNET_POSTSTOP:+${VNET_POSTSTOP}\n}  exec.poststop += \"${bastille_sharedir}/vnet delete ${iface} ${iface}_${NAME}\";"
    fi
}

validate_netconf() {
    if [ -n "${bastille_jail_loopback}" ] && [ -n "${bastille_jail_interface}" ] && [ -n "${bastille_jail_external}" ]; then
        echo -e "${COLOR_RED}Invalid network configuration.${COLOR_RESET}"
        exit 1
    fi
    if [ -n "${bastille_jail_external}" ]; then
        return 0
    elif [ ! -z "${bastille_jail_loopback}" ] && [ -z "${bastille_jail_external}" ]; then
        if [ -z "${bastille_jail_interface}" ]; then
            echo -e "${COLOR_RED}Invalid network configuration.${COLOR_RESET}"
            exit 1
        fi
    elif [ -z "${bastille_jail_loopback}" ] && [ ! -z "${bastille_jail_interface}" ]; then
        echo -e "${COLOR_RED}Invalid network configuration.${COLOR_RESET}"
        exit 1
    elif [ -z "${bastille_jail_external}" ]; then
        echo -e "${COLOR_RED}Invalid network configuration.${COLOR_RESET}"
        exit 1
    fi
}

validate_release() {
    ## check release name match, else show usage
    if [ -n "${NAME_VERIFY}" ]; then
        RELEASE="${NAME_VERIFY}"
    else
        usage
    fi
}

generate_jail_conf() {
    cat << EOF > "${bastille_jail_conf}"
${NAME} {
  devfs_ruleset = 4;
  enforce_statfs = 2;
  exec.clean;
  exec.consolelog = ${bastille_jail_log};
  exec.start = '/bin/sh /etc/rc';
  exec.stop = '/bin/sh /etc/rc.shutdown';
  host.hostname = ${NAME};
  mount.devfs;
  mount.fstab = ${bastille_jail_fstab};
  path = ${bastille_jail_path};
  securelevel = 2;

${IP4_ADDR_LINES:+$IP4_ADDR_LINES}
${IP6_ADDR_LINES:+$IP6_ADDR_LINES}
  ip6 = ${IP6_MODE};
}
EOF
}

generate_vnet_jail_conf() {
    ## generate config
    cat << EOF > "${bastille_jail_conf}"
${NAME} {
  devfs_ruleset = 13;
  enforce_statfs = 2;
  exec.clean;
  exec.consolelog = ${bastille_jail_log};
  exec.start = '/bin/sh /etc/rc';
  exec.stop = '/bin/sh /etc/rc.shutdown';
  host.hostname = ${NAME};
  mount.devfs;
  mount.fstab = ${bastille_jail_fstab};
  path = ${bastille_jail_path};
  securelevel = 2;

  vnet;
  vnet.interface = ${JAIL_INTERFACES};
${VNET_PRESTART_LINES}
  # workaround
  # https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=238326
${VNET_PRESTOP_LINES}
${VNET_POSTSTOP_LINES}
}
EOF
}

create_jail() {
    bastille_jail_base="${bastille_jailsdir}/${NAME}/root/.bastille"  ## dir
    bastille_jail_template="${bastille_jailsdir}/${NAME}/root/.template"  ## dir
    bastille_jail_path="${bastille_jailsdir}/${NAME}/root"  ## dir
    bastille_jail_fstab="${bastille_jailsdir}/${NAME}/fstab"  ## file
    bastille_jail_conf="${bastille_jailsdir}/${NAME}/jail.conf"  ## file
    bastille_jail_log="${bastille_logsdir}/${NAME}_console.log"  ## file
    bastille_jail_rc_conf="${bastille_jailsdir}/${NAME}/root/etc/rc.conf" ## file
    bastille_jail_resolv_conf="${bastille_jailsdir}/${NAME}/root/etc/resolv.conf" ## file

    if [ ! -d "${bastille_jailsdir}/${NAME}" ]; then
        if [ "${bastille_zfs_enable}" = "YES" ]; then
            if [ -n "${bastille_zfs_zpool}" ]; then
                ## create required zfs datasets, mountpoint inherited from system
                zfs create ${bastille_zfs_options} "${bastille_zfs_zpool}/${bastille_zfs_prefix}/jails/${NAME}"
                if [ -z "${THICK_JAIL}" ]; then
                    zfs create ${bastille_zfs_options} "${bastille_zfs_zpool}/${bastille_zfs_prefix}/jails/${NAME}/root"
                fi
            fi
        else
            mkdir -p "${bastille_jailsdir}/${NAME}"
        fi
    fi

    if [ ! -d "${bastille_jail_base}" ]; then
        mkdir -p "${bastille_jail_base}"
    fi

    if [ ! -d "${bastille_jail_path}/usr/home" ]; then
        mkdir -p "${bastille_jail_path}/usr/home"
    fi

    if [ ! -d "${bastille_jail_path}/usr/local" ]; then
        mkdir -p "${bastille_jail_path}/usr/local"
    fi

    if [ ! -d "${bastille_jail_template}" ]; then
        mkdir -p "${bastille_jail_template}"
    fi

    if [ ! -f "${bastille_jail_fstab}" ]; then
        if [ -z "${THICK_JAIL}" ]; then
            echo -e "${bastille_releasesdir}/${RELEASE} ${bastille_jail_base} nullfs ro 0 0" > "${bastille_jail_fstab}"
        else
            touch "${bastille_jail_fstab}"
        fi
    fi

    if [ ! -f "${bastille_jail_conf}" ]; then
        ## generate the jail configuration file 
        if [ -n "${VNET_JAIL}" ]; then
            generate_vnet_jail_conf
        else
            generate_jail_conf
        fi
    fi

    ## using relative paths here
    ## MAKE SURE WE'RE IN THE RIGHT PLACE
    cd "${bastille_jail_path}"
    echo
    printf "${COLOR_GREEN}NAME: %s%s${COLOR_RESET}\n" "${NAME}" "${VNET_JAIL:+ (VNET)}"
    printf "${COLOR_GREEN}IP: %s${COLOR_RESET}\n" "${IP}"
    if [ -n  "${OPTIONS}" ]; then
        printf "${COLOR_GREEN}OPTIONS: %s${COLOR_RESET}\n" "${OPTIONS}"
    fi
    printf "${COLOR_GREEN}RELEASE: %s${COLOR_RESET}\n" "${RELEASE}"
    echo

    if [ -z "${THICK_JAIL}" ]; then
        for _link in bin boot lib libexec rescue sbin usr/bin usr/include usr/lib usr/lib32 usr/libdata usr/libexec usr/sbin usr/share usr/src; do
            ln -sf /.bastille/${_link} ${_link}
        done
    fi

    ## link home properly
    ln -s usr/home home

    if [ -z "${THICK_JAIL}" ]; then
        ## rw
        ## copy only required files for thin jails
        FILE_LIST=".cshrc .profile COPYRIGHT dev etc media mnt net proc root tmp var usr/obj usr/tests"
        for files in ${FILE_LIST}; do
            if [ -f "${bastille_releasesdir}/${RELEASE}/${files}" ] || [ -d "${bastille_releasesdir}/${RELEASE}/${files}" ]; then
                cp -a "${bastille_releasesdir}/${RELEASE}/${files}" "${bastille_jail_path}/${files}"
                if [ "$?" -ne 0 ]; then
                    ## notify and clean stale files/directories
                    echo -e "${COLOR_RED}Failed to copy release files, please retry create!${COLOR_RESET}"
                    bastille destroy "${NAME}"
                    exit 1
                fi
            fi
        done
    else
        echo -e "${COLOR_GREEN}Creating a thickjail, this may take a while...${COLOR_RESET}"
        if [ "${bastille_zfs_enable}" = "YES" ]; then
            if [ -n "${bastille_zfs_zpool}" ]; then
                ## perform release base replication

                ## sane bastille zfs options 
                ZFS_OPTIONS=$(echo ${bastille_zfs_options} | sed 's/-o//g')

                ## take a temp snapshot of the base release
                SNAP_NAME="bastille-$(date +%Y-%m-%d-%H%M%S)"
                zfs snapshot "${bastille_zfs_zpool}/${bastille_zfs_prefix}/releases/${RELEASE}"@"${SNAP_NAME}"

                ## replicate the release base to the new thickjail and set the default mountpoint
                zfs send -R "${bastille_zfs_zpool}/${bastille_zfs_prefix}/releases/${RELEASE}"@"${SNAP_NAME}" | \
                zfs receive "${bastille_zfs_zpool}/${bastille_zfs_prefix}/jails/${NAME}/root"
                zfs set ${ZFS_OPTIONS} mountpoint=none "${bastille_zfs_zpool}/${bastille_zfs_prefix}/jails/${NAME}/root"
                zfs inherit mountpoint "${bastille_zfs_zpool}/${bastille_zfs_prefix}/jails/${NAME}/root"

                ## cleanup temp snapshots initially
                zfs destroy "${bastille_zfs_zpool}/${bastille_zfs_prefix}/releases/${RELEASE}"@"${SNAP_NAME}"
                zfs destroy "${bastille_zfs_zpool}/${bastille_zfs_prefix}/jails/${NAME}/root"@"${SNAP_NAME}"

                if [ "$?" -ne 0 ]; then
                    ## notify and clean stale files/directories
                    echo -e "${COLOR_RED}Failed release base replication, please retry create!${COLOR_RESET}"
                    bastille destroy "${NAME}"
                    exit 1
                fi
            fi
        else
            ## copy all files for thick jails
            cp -a "${bastille_releasesdir}/${RELEASE}/" "${bastille_jail_path}"
            if [ "$?" -ne 0 ]; then
                ## notify and clean stale files/directories
                echo -e "${COLOR_RED}Failed to copy release files, please retry create!${COLOR_RESET}"
                bastille destroy "${NAME}"
                exit 1
            fi
        fi
    fi

    ## rc.conf
    ##  + syslogd_flags="-ss"
    ##  + sendmail_none="NONE"
    ##  + cron_flags="-J 60" ## cedwards 20181118
    if [ ! -f "${bastille_jail_rc_conf}" ]; then
        touch "${bastille_jail_rc_conf}"
        sysrc -f "${bastille_jail_rc_conf}" syslogd_flags=-ss
        sysrc -f "${bastille_jail_rc_conf}" sendmail_enable=NONE
        sysrc -f "${bastille_jail_rc_conf}" cron_flags='-J 60'

        ## VNET specific
        if [ -n "${VNET_JAIL}" ]; then
            ## if 0.0.0.0 set SYNCDHCP(IPv4)
            ## else if :: use SLAAC(IPv6)
            ## else set static IPv4 or IPv6 address
            echo $RC_CONF_LINES | xargs -n1 /usr/sbin/sysrc -f "${bastille_jail_rc_conf}"

            ## Add default route and/or other options in jails rc.conf.
            local opt gwaddr key value
            local optlist="${OPTIONS}"
            while [ ${#optlist} -gt 0 ]; do
                case "${optlist}" in
                    *,*)
                        opt=${optlist%%,*}
                        optlist=${optlist#*,}
                        ;;
                    *)
                        opt=$optlist
                        optlist=""
                        ;;
                esac
                case "${opt}" in
                    gw=*|gateway=*)
                        gwaddr=${opt#*=}
                        if is_ip6 $gwaddr; then
                            /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" ipv6_defaultrouter="${gwaddr}"
                        else
                            /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" defaultrouter="${gwaddr}"
                        fi
                        ;;
                    router)
                        /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" gateway_enable=YES
                        /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" ipv6_gateway_enable=YES
                        ;;
                    ipv4router)
                        /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" gateway_enable=YES
                        ;;
                    ipv6router)
                        /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" ipv6_gateway_enable=YES
                        ;;
                    *=*)
                        key=${opt%%=*}
                        value=${opt#*=}
                        value=$(echo $value | sed 's/"/\\"/g')
                        /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" $key="$value"
                        ;;
                esac
            done
        fi
    fi

    ## resolv.conf (default: copy from host unless VNET_ISOLATED)
    if [ -n "$VNET_ISOLATED" ]; then
        echo -e "${COLOR_YELLOW}Isolated. Not going to copy resolv.conf from the host.${COLOR_RESET}"
    elif [ ! -f "${bastille_jail_resolv_conf}" ]; then
        cp -L "${bastille_resolv_conf}" "${bastille_jail_resolv_conf}"
    fi

    ## TZ: configurable (default: etc/UTC)
    ln -s "/usr/share/zoneinfo/${bastille_tzdata}" etc/localtime
}

# Handle special-case commands first.
case "$1" in
help|-h|--help)
    usage
    ;;
esac

if echo "$3" | grep '@'; then
    BASTILLE_JAIL_IP=$(echo "$3" | awk -F@ '{print $2}')
    BASTILLE_JAIL_INTERFACES=$( echo "$3" | awk -F@ '{print $1}')
fi

## reset this options
THICK_JAIL=""
VNET_JAIL=""
VNET_VIRTIF=""
VNET_ISOLATED="1"
VNET_PRESTART=""
VNET_PRESTOP=""
VNET_POSTSTOP=""
IFLIST=""
RC_CONF=""

## handle combined options then shift
if [ "${1}" = "-T" -o "${1}" = "--thick" -o "${1}" = "thick" ] && \
    [ "${2}" = "-V" -o "${2}" = "--vnet" -o "${2}" = "vnet" ]; then
    THICK_JAIL="1"
    VNET_JAIL="1"
    shift 2
else
    ## handle single options
    case "${1}" in
        -T|--thick|thick)
            shift
            THICK_JAIL="1"
            ;;
        -V|--vnet|vnet)
            shift
            VNET_JAIL="1"
            ;;
        -*)
            echo -e "${COLOR_RED}Unknown Option.${COLOR_RESET}"
            usage
            ;;
    esac
fi

NAME="$1"
RELEASE="$2"
IP="$3"
OPTIONS="$4"

if [ $# -gt 4 ] || [ $# -lt 3 ]; then
    usage
fi

## don't allow for dots(.) in container names
if echo "${NAME}" | grep -q "[.]"; then
    echo -e "${COLOR_RED}Container names may not contain a dot(.)!${COLOR_RESET}"
    exit 1
fi

## verify release
case "${RELEASE}" in
*-RELEASE|*-release|*-RC1|*-rc1|*-RC2|*-rc2)
    ## check for FreeBSD releases name
    NAME_VERIFY=$(echo "${RELEASE}" | grep -iwE '^([1-9]{2,2})\.[0-9](-RELEASE|-RC[1-2])$' | tr '[:lower:]' '[:upper:]')
    validate_release
    ;;
*-stable-LAST|*-STABLE-last|*-stable-last|*-STABLE-LAST)
    ## check for HardenedBSD releases name(previous infrastructure)
    NAME_VERIFY=$(echo "${RELEASE}" | grep -iwE '^([1-9]{2,2})(-stable-last)$' | sed 's/STABLE/stable/g' | sed 's/last/LAST/g')
    validate_release
    ;;
*-stable-build-[0-9]*|*-STABLE-BUILD-[0-9]*)
    ## check for HardenedBSD(specific stable build releases)
    NAME_VERIFY=$(echo "${RELEASE}" | grep -iwE '([0-9]{1,2})(-stable-build)-([0-9]{1,3})$' | sed 's/BUILD/build/g' | sed 's/STABLE/stable/g')
    validate_release
    ;;
*-stable-build-latest|*-stable-BUILD-LATEST|*-STABLE-BUILD-LATEST)
    ## check for HardenedBSD(latest stable build release)
    NAME_VERIFY=$(echo "${RELEASE}" | grep -iwE '([0-9]{1,2})(-stable-build-latest)$' | sed 's/STABLE/stable/g' | sed 's/build/BUILD/g' | sed 's/latest/LATEST/g')
    validate_release
    ;;
current-build-[0-9]*|CURRENT-BUILD-[0-9]*)
    ## check for HardenedBSD(specific current build releases)
    NAME_VERIFY=$(echo "${RELEASE}" | grep -iwE '(current-build)-([0-9]{1,3})' | sed 's/BUILD/build/g' | sed 's/CURRENT/current/g')
    validate_release
    ;;
current-build-latest|current-BUILD-LATEST|CURRENT-BUILD-LATEST)
    ## check for HardenedBSD(latest current build release)
    NAME_VERIFY=$(echo "${RELEASE}" | grep -iwE '(current-build-latest)' | sed 's/CURRENT/current/g' | sed 's/build/BUILD/g' | sed 's/latest/LATEST/g')
    validate_release
    ;;
*)
    echo -e "${COLOR_RED}Unknown Release.${COLOR_RESET}"
    usage
    ;;
esac

## check for name/root/.bastille
if [ -d "${bastille_jailsdir}/${NAME}/root/.bastille" ]; then
    echo -e "${COLOR_RED}Jail: ${NAME} already created. ${NAME}/root/.bastille exists.${COLOR_RESET}"
    exit 1
fi

## check for required release
if [ ! -d "${bastille_releasesdir}/${RELEASE}" ]; then
    echo -e "${COLOR_RED}Release must be bootstrapped first; see 'bastille bootstrap'.${COLOR_RESET}"
    exit 1
fi

## check if a running jail matches name or already exist
if [ -n "${NAME}" ]; then
    running_jail
fi

## check if ip address is valid
if [ -n "${IP}" ]; then
    validate_all_ip "$IP"
else
    usage
fi
VNET_PRESTART_LINES=$(echo -e "$VNET_PRESTART" | sort | uniq)
VNET_PRESTOP_LINES=$(echo -e "$VNET_PRESTOP" | sort | uniq)
VNET_POSTSTOP_LINES=$(echo -e "$VNET_POSTSTOP" | sort | uniq)
JAIL_INTERFACES=$(echo $(echo -e "$IFLIST" | sort | uniq) | tr " " ",")
IP4_ADDR_LINES=$(echo -e "$IP4_ADDR")
IP6_ADDR_LINES=$(echo -e "$IP6_ADDR")
RC_CONF_LINES=$(echo -e "$RC_CONF")

if [ -n "${VNET_JAIL}" ]; then
    if [ -z "${JAIL_INTERFACES}" ]; then
        echo -e "${COLOR_RED}Specify interfaces or networks for VNET jails.${COLOR_RESET}"
        exit 1
    fi
else
    validate_netconf
    VNET_ISOLATED=""
fi

create_jail
