#!/bin/sh

# Copyright - negotiable
copyright ()
{
cat << VERBATUM_COPYRIGHT_HEADER_INCLUDE_NEGOTIABLE
# easytls-cryptv2-client-connect.sh -- Do simple magic
#
# Copyright (C) 2020 Richard Bonhomme (Friday 13th of March 2020)
# https://github.com/TinCanTech/easy-tls
# tincanteksup@gmail.com
# All Rights reserved.
#
# This code is released under version 2 of the GNU GPL
# See LICENSE of this project for full licensing details.
#
# Acknowledgement:
# syzzer: https://github.com/OpenVPN/openvpn/blob/master/doc/tls-crypt-v2.txt
#
# Lock client connections to specific client devices.
#
VERBATUM_COPYRIGHT_HEADER_INCLUDE_NEGOTIABLE
}

# This is here to catch "print" statements
# Wrapper around printf - clobber print since it's not POSIX anyway
# shellcheck disable=SC1117
print() { printf "%s\n" "$1"; }

# Exit on error
die ()
{
	[ -n "$help_note" ] && printf "\n%s\n" "$help_note"
	printf "\n%s\n" "ERROR: $1"
	printf "%s\n" "https://github.com/TinCanTech/easy-tls"
	exit "${2:-255}"
}

# Tls-crypt-v2-verify failure, not an error.
fail_and_exit ()
{
	if [ $TLS_CRYPT_V2_VERIFY_VERBOSE ]
	then
		printf "%s " "$easytls_msg"
		[ -z "$success_msg" ] || printf "%s\n" "$success_msg"
		printf "%s\n%s\n" "$failure_msg $common_name" "$1"

		printf "%s\n" "https://github.com/TinCanTech/easy-tls"
	else
		printf "%s %s %s\n" "$easytls_msg" \
			"$success_msg" "$failure_msg"
	fi
	exit "${2:-254}"
} # => fail_and_exit ()

# Help
help_text ()
{
	help_msg='
  easytls-cryptv2-client-connect.sh

  This script is intended to be used by tls-crypt-v2 client keys
  generated by EasyTLS.  See: https://github.com/TinCanTech/easy-tls

  Options:
  help|-h|--help      This help text.
  -v|--verbose        Be a lot more verbose at run time (Not Windows).
  -t|--tmp-dir=<path> Temporary directory to load the client hardware list from.

  Exit codes:
  0   - Allow connection, Client key has passed all tests.
  1   - Disallow connection, client key has passed all tests but is REVOKED.
  2   - Disallow connection, serial number is disabled.

  253 - Disallow connection, exit code when --help is called.
  254 - BUG Disallow connection, fail_and_exit() exited with default error code.
  255 - BUG Disallow connection, die() exited with default error code.
'
	printf "%s\n" "$help_msg"

	# For secrity, --help must exit with an error
	exit 253
}

# Get the client serial number from env
get_client_serial ()
{
	printf '%s' "$tls_serial_hex_0" | sed 's/://g' | awk '{print toupper($0)}'
}

# Get the client hardware address from env
get_client_hwaddr ()
{
	printf '%s' "$IV_HWADDR" | sed 's/://g'
}

# Verify the client serial
verify_client_serial ()
{
	[ -z "$client_serial" ] && { 
		help_note="Failed to set client serial number: $client_serial"
		return 1
		}

	return 0
}

# Verify the pushed hardware address
verify_client_hwaddr ()
{
	[ -z "$client_hwaddr" ] && {
		failure_msg="Client $common_name did not push a Hardware Address!"
		return 1
		}

	[ 12 -eq ${#client_hwaddr} ] || {
		failure_msg="Hardware Address must be 12 digits exactly!"
		return 1
		}

	printf '%s\n' "$client_hwaddr" | grep -q '^[[:xdigit:]]\{12\}$' || {
		failure_msg="Hardware Adress must be hexidecimal digits!"
		return 1
		}

	return 0
}

# Verify the pushed hwaddr is in the key list
verify_allowed_hwaddr ()
{
	grep -q "$client_hwaddr" "$client_hwaddr_file"
}

# Allow connection
connection_allowed ()
{
	absolute_fail=0
}

# Initialise
init ()
{
	# Fail by design
	absolute_fail=1

	# Default temp dir
	EASYTLS_TMP_DIR="/tmp"

	# Log message
	easytls_msg="* EasyTLS-cryptv2-client-connect ==>"
}

# Dependancies
deps ()
{
	# Client certificate serial number
	client_serial="$(get_client_serial)"
	verify_client_serial || die "CLIENT SERIAL"
}

#######################################

# Initialise
init


# Options
while [ -n "$1" ]
do
	# Separate option from value:
	opt="${1%%=*}"
	val="${1#*=}"
	empty_ok="" # Empty values are not allowed unless expected

	case "$opt" in
	help|-h|-help|--help)
		empty_ok=1
		help_text
	;;
	-v|--verbose)
		empty_ok=1
		TLS_CRYPT_V2_VERIFY_VERBOSE=1
	;;
	-t|--tmp-dir)
		EASYTLS_TMP_DIR="$val"
	;;
	-r|--require-pushed-hwaddr)
		empty_ok=1
		EASYTLS_hwaddr_required=1
	;;
	*)
		empty_ok=1
		print "Ignoring unknown option: $1"
	;;
	esac

	# fatal error when no value was provided
	if [ ! $empty_ok ] && { [ "$val" = "$1" ] || [ -z "$val" ]; }; then
		die "Missing value to option: $opt" 21
	fi

	shift
done

# Dependencies
deps

# File name
client_hwaddr_file="$EASYTLS_TMP_DIR/$client_serial.$daemon_pid"

# Get client pushed hardware address
client_hwaddr="$(get_client_hwaddr)"

# Does the hardware-address-list file exist
if [ -f "$client_hwaddr_file" ]
then
	failure_msg="Hardware address $client_hwaddr not allowed"

	# Client pushed IV_HWADDR - Required for this client
	verify_client_hwaddr || fail_and_exit "CLIENT IV_HWADDR"

	verify_allowed_hwaddr && {
		unset failure_msg
		success_msg="Hardware address correct: $common_name $client_hwaddr"
		connection_allowed
		}
else
	# If the file does not exist then this client is not bound to hardware
	# Decide on how strict you want your server to be

	success_msg="Hardware list file not found: $client_hwaddr_file"

	[ $EASYTLS_hwaddr_required ] && {
		# Client pushed IV_HWADDR - Required for this client
		verify_client_hwaddr || fail_and_exit "CLIENT IV_HWADDR"
		}

	connection_allowed
fi


# Any failure_msg means fail_and_exit
[ "$failure_msg" ] && fail_and_exit "NEIN" 9

# For DUBUG
[ "$FORCE_ABSOLUTE_FAIL" ] && absolute_fail=1 && \
	failure_msg="FORCE_ABSOLUTE_FAIL"

# There is only one way out of this...
[ $absolute_fail -eq 0 ] || fail_and_exit "ABSOLUTE_FAIL" 9

# All is well
[ $TLS_CRYPT_V2_VERIFY_VERBOSE ] && \
	printf "%s\n" "<EXOK> $easytls_msg $success_msg"

exit 0