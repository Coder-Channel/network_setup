#!/bin/bash

if ! command -v nmcli 2>&1 >/dev/null; then
    echo "This script requires nmcli, which isn't found"
    exit 1
fi

if ! command -v ip 2>&1 >/dev/null; then
    echo "This script requires ip, which isn't found"
    exit 1
fi

help_string="Usage: ./network_setup.sh [OPTIONS]
Configure default network interface

OPTIONS
  -i	ipv4 address and mask in the format 127.0.0.1/32
  -g	gateway
  -y	disable confirmation dialog
  -h	show list of command line options

Running the command without any options will show current configuration without any changes"

function check_ip() {
    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local old_ifs="${IFS}"

        IFS="."
        for val in $1; do
            if ((10#$val < 0 || 10#$val > 255)); then
                IFS="${old_ifs}"
                return 1
            fi
        done

        IFS="/"
        read -r _ mask <<< "$1"

        if ((10#$mask < 0 || 10#$mask > 32)); then
            IFS="${old_ifs}"
            return 1
        fi

        IFS="${old_ifs}"
        return 0
    fi

    return 1
}

function check_gateway() {
    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local old_ifs="${IFS}"

        IFS="."
        for val in $1; do
            if ((10#$val < 0 || 10#$val > 255)); then
                IFS="${old_ifs}"
                return 1
            fi
        done

        IFS="${old_ifs}"
        return 0
    fi

    return 1
}

function print_info() {
    info="$(ip -j route show dev "$1")"
    echo "$(echo "${info}" | sed 's|.*"prefsrc":"\([0-9.]*\)".*}.*|IP address: \1|')"
    echo "$(echo "${info}" | sed 's|.*"dst":"[0-9.]*/\([0-9]*\)".*}.*|Mask: \1|')"
    echo "$(echo "${info}" | sed 's|.*"gateway":"\([0-9.]*\)".*}.*|Gateway: \1|')"
}

while getopts ":i:m:g:syh" opt; do
    case "${opt}" in
        i)
            address="${OPTARG}"
            if ! check_ip "${address}"; then
                echo "Invalid option: invalid ipv4 address/mask"
                exit 1
            fi
            ;;
        g)
            gateway="${OPTARG}"
            if ! check_gateway "${gateway}"; then
                echo "Invalid option: invalid gateway"
                exit 1
            fi
            ;;
        y)
            no_confirm=1
            ;;
        h)
            echo "${help_string}"
            exit 0
            ;;
        \?)
            echo "Invalid option: ${OPTARG}"
            exit 1
            ;;
        :)
            echo "Invalid option: ${OPTARG} requires an argument"
            exit 1
            ;;
    esac
done

if ! test -n "${address-}"; then
    if ! test -n "${gateway-}"; then
        echo -e "Nothing to do\n"

        device="$(ip route show default | sed 's|.*dev \(\w*\).*|\1|')"
        if [[ $? != 0 ]]; then
            echo "Ip error!"
            exit 1
        fi

        print_info "${device}"

        exit 0
    fi
fi

if ! test -n "${no_confirm-}"; then
    read -ep $'Running this script may affect your network connection. Are you sure?\n[y/N]: ' confirm
    [[ "${confirm}" != [Yy]* ]] && exit 0
fi

# Fedora does not have an /etc/network/interfaces file,
# instead relying on NetworkManager for network configuration.
# Modern Ubuntu also doesn't have it, using Netplan instead.
# I use Fedora, so this script is made for NetworkManager.
# The standard way to do this is using nmcli, directly modifying config
# files isn't really an option.

device="$(ip route show default | sed 's|.*dev \(\w*\).*|\1|')"
if [[ $? != 0 ]]; then
    echo "Ip error!"
    exit 1
fi

connection="$(nmcli -g DEVICE,UUID connection show | sed -n "s|^${device}:\(.*\)|\1|p" | head -1)"
if [[ $? != 0 ]]; then
    echo "Nmcli error!"
    exit 1
fi

if ! test -n "${address}"; then
    address=$(nmcli -g IP4.ADDRESS connection show "${connection}" | sed 's| \| | |')
    if [[ $? != 0 ]]; then
        echo "Nmcli error!"
        exit 1
    fi
fi

if ! test -n "${gateway}"; then
    gateway=$(nmcli -g IP4.GATEWAY connection show "${connection}")
    if [[ $? != 0 ]]; then
        echo "Nmcli error!"
        exit 1
    fi
fi

nmcli connection modify "${connection}" ipv4.method manual ipv4.addresses "${address}" ipv4.gateway "${gateway}" >/dev/null
if [[ $? != 0 ]]; then
    echo "Nmcli error!"
    exit 1
fi

nmcli connection down "${connection}" >/dev/null
if [[ $? != 0 ]]; then
    echo "Nmcli error!"
    exit 1
fi

nmcli connection up "${connection}" >/dev/null
if [[ $? != 0 ]]; then
    echo "Nmcli error!"
    exit 1
fi

print_info "${device}"

