#!/bin/sh

# Copyright - negotiable
copyright ()
{
: << VERBATUM_COPYRIGHT_HEADER_INCLUDE_NEGOTIABLE
# easytls-client-connect.sh -- Do simple magic
#
# Copyright (C) 2020 Richard Bonhomme (Friday 13th of March 2020)
# https://github.com/TinCanTech/easy-tls
# tincantech@protonmail.com
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

# Help
help_text ()
{
	help_msg="
  easytls-client-connect.sh

  This script is intended to be used by tls-crypt-v2 client keys
  generated by EasyTLS.  See: https://github.com/TinCanTech/easy-tls

  Options:
  help|-h|--help         This help text.
  -v|--verbose           Be a lot more verbose at run time (Not Windows).
  -a|--allow-no-check    If the key has a hardware-address configured
                         and the client did NOT use --push-peer-info
                         then allow the connection.  Otherwise, keys with a
                         hardware-address MUST use --push-peer-info.
  -p|--push-required     Require all clients to use --push-peer-info.
  -k|--key-required      Require all client keys to have a hardware-address.
  -t|--tmp-dir=<DIR>     Temp directory where server-scripts write data.
                         Default: *nix /tmp/easytls
                                  Windows C:/Windows/Temp/easytls
  -b|--base-dir=<DIR>    Path to OpenVPN base directory. (Windows Only)
                         Default: C:/Progra~1/OpenVPN
  -o|--ovpnbin-dir=<DIR> Path to OpenVPN bin directory. (Windows Only)
                         Default: C:/Progra~1/OpenVPN/bin
  -e|--ersabin-dir=<DIR> Path to Easy-RSA3 bin directory. (Windows Only)
                         Default: C:/Progra~1/Openvpn/easy-rsa/bin

  Exit codes:
  0   - Allow connection, Client hwaddr is correct or not required.
  2   - Disallow connection, pushed hwaddr does not match.
  3   - Disallow connection, hwaddr required and not pushed.
  4   - Disallow connection, hwaddr required and not keyed.
  5   - Disallow connection, Kill client.
  7   - Disallow connection, X509 certificate incorrect for this TLS-key.
  8   - Disallow connection, missing X509 client cert serial. (BUG)
  9   - Disallow connection, unexpected failure. (BUG)
  21  - USER ERROR Disallow connection, options error.

  60  - USER ERROR Disallow connection, missing Temp dir
  61  - USER ERROR Disallow connection, missing Base dir
  62  - USER ERROR Disallow connection, missing Easy-RSA bin dir
  63  - USER ERROR Disallow connection, missing Openvpn bin dir
  64  - USER ERROR Disallow connection, missing openssl.exe
  65  - USER ERROR Disallow connection, missing cat.exe
  66  - USER ERROR Disallow connection, missing date.exe
  67  - USER ERROR Disallow connection, missing grep.exe
  68  - USER ERROR Disallow connection, missing sed.exe
  69  - USER ERROR Disallow connection, missing printf.exe
  70  - USER ERROR Disallow connection, missing rm.exe

  253 - Disallow connection, exit code when --help is called.
  254 - BUG Disallow connection, fail_and_exit() exited with default error code.
  255 - BUG Disallow connection, die() exited with default error code.
"
	print "${help_msg}"

	# For secrity, --help must exit with an error
	exit 253
}

# Wrapper around 'printf' - clobber 'print' since it's not POSIX anyway
# shellcheck disable=SC1117
print () { "${EASYTLS_PRINTF}" "%s\n" "${1}"; }
verbose_print () { [ "${EASYTLS_VERBOSE}" ] && print "${1}"; return 0; }

# Exit on error
die ()
{
	delete_metadata_files
	verbose_print "<ERROR> ${status_msg}"
	[ -n "${help_note}" ] && print "${help_note}"
	print "ERROR: ${1}"
	[ $EASYTLS_FOR_WINDOWS ] && "${EASYTLS_PRINTF}" "%s\n%s\n" \
		"<ERROR> ${status_msg}" "ERROR: ${1}" > "${EASYTLS_WLOG}"
	exit "${2:-255}"
}

# failure not an error
fail_and_exit ()
{
	delete_metadata_files
	verbose_print "<FAIL> ${status_msg}"
	print "${status_msg}"
	print "${failure_msg}"
	print "${1}"
	[ $EASYTLS_FOR_WINDOWS ] && "${EASYTLS_PRINTF}" "%s\n%s\n" \
		"<FAIL> ${status_msg}" "${failure_msg}" "${1}" > "${EASYTLS_WLOG}"
	exit "${2:-254}"
} # => fail_and_exit ()

# Delete all metadata files
delete_metadata_files ()
{
	"${EASYTLS_RM}" -f \
		"${generic_metadata_file}" \
		"${generic_ext_md_file}" \
		"${generic_trusted_md_file}" \
		"${client_metadata_file}" \
		"${client_ext_md_file}" \
		"${client_trusted_md_file}" \
		"${stage1_file}" \
		"${g_x509_serial_md_file}" \
		"${EASYTLS_KILL_FILE}" \

	update_status "temp-files deleted"
}

# Log fatal warnings
warn_die ()
{
	if [ -n "${1}" ]
	then
		fatal_msg="${fatal_msg}
${1}"
	else
		[ -z "${fatal_msg}" ] || die "${fatal_msg}" 21
	fi
}

# Update status message
update_status ()
{
	status_msg="${status_msg} => ${*}"
}

# Remove colons ':' and up-case
format_number ()
{
	"${EASYTLS_PRINTF}" '%s' "${1}" | \
		"${EASYTLS_SED}" -e 's/://g' -e 'y/abcdef/ABCDEF/'
}

# Allow connection
connection_allowed ()
{
	delete_metadata_files
	absolute_fail=0
	update_status "connection allowed"
}

# Initialise
init ()
{
	# Fail by design
	absolute_fail=1

	# Defaults
	EASYTLS_srv_pid=$PPID

	# Log message
	status_msg="* EasyTLS-client-connect"

	# Identify Windows
	EASYRSA_KSH='@(#)MIRBSD KSH R39-w32-beta14 $Date: 2013/06/28 21:28:57 $'
	[ "${KSH_VERSION}" = "${EASYRSA_KSH}" ] && EASYTLS_FOR_WINDOWS=1

	# Required binaries
	EASYTLS_OPENSSL='openssl'
	EASYTLS_CAT='cat'
	EASYTLS_DATE='date'
	EASYTLS_GREP='grep'
	EASYTLS_SED='sed'
	EASYTLS_PRINTF='printf'
	EASYTLS_RM='rm'

	# Directories and files
	if [ $EASYTLS_FOR_WINDOWS ]
	then
		# Windows
		host_drv="${PATH%%\:*}"
		base_dir="${EASYTLS_base_dir:-${host_drv}:/Progra~1/Openvpn}"
		EASYTLS_ersabin_dir="${EASYTLS_ersabin_dir:-${base_dir}/easy-rsa/bin}"
		EASYTLS_ovpnbin_dir="${EASYTLS_ovpnbin_dir:-${base_dir}/bin}"

		[ -d "${base_dir}" ] || exit 61
		[ -d "${EASYTLS_ersabin_dir}" ] || exit 62
		[ -d "${EASYTLS_ovpnbin_dir}" ] || exit 63
		[ -f "${EASYTLS_ovpnbin_dir}/${EASYTLS_OPENSSL}.exe" ] || exit 64
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_CAT}.exe" ] || exit 65
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_DATE}.exe" ] || exit 66
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_GREP}.exe" ] || exit 67
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_SED}.exe" ] || exit 68
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_PRINTF}.exe" ] || exit 69
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_RM}.exe" ] || exit 70

		export PATH="${EASYTLS_ersabin_dir};${EASYTLS_ovpnbin_dir};${PATH}"
	fi
} # => init ()

# Dependancies
deps ()
{
	if [ $EASYTLS_FOR_WINDOWS ]
	then
		WIN_TEMP="${host_drv}:/Windows/Temp"
		export EASYTLS_tmp_dir="${EASYTLS_tmp_dir:-${WIN_TEMP}}"
	else
		export EASYTLS_tmp_dir="${EASYTLS_tmp_dir:-/tmp}"
	fi

	# Test temp dir
	[ -d "${EASYTLS_tmp_dir}" ] || exit 60

	# Windows log
	EASYTLS_WLOG="${EASYTLS_tmp_dir}/easytls-cc.log.${EASYTLS_srv_pid}"

	# Kill client file
	EASYTLS_KILL_FILE="${EASYTLS_tmp_dir}/kill-client.${EASYTLS_srv_pid}"
}

#######################################

# Initialise
init

# Options
while [ -n "${1}" ]
do
	# Separate option from value:
	opt="${1%%=*}"
	val="${1#*=}"
	empty_ok="" # Empty values are not allowed unless expected

	case "${opt}" in
	help|-h|--help)
		empty_ok=1
		help_text
	;;
	-v|--verbose)
		empty_ok=1
		EASYTLS_VERBOSE=1
	;;
	-a|--allow-no-check)
		empty_ok=1
		allow_no_check=1
	;;
	-p|--push-hwaddr-required)
		empty_ok=1
		push_hwaddr_required=1
	;;
	-k|--key-hwaddr-required)
		empty_ok=1
		key_hwaddr_required=1
	;;
	-b|--base-dir)
		EASYTLS_base_dir="${val}"
	;;
	-t|--tmp-dir)
		EASYTLS_tmp_dir="${val}"
	;;
	-o|--openvpn-bin-dir)
		EASYTLS_ovpnbin_dir="${val}"
	;;
	-e|--easyrsa-bin-dir)
		EASYTLS_ersabin_dir="${val}"
	;;
	*)
		empty_ok=1
		if [ -f "${opt}" ]
		then
			# Do not need this in the log but keep it here for reference
			#[ $EASYTLS_VERBOSE ] && echo "Ignoring temp file: $opt"
			:
		else
			[ "${EASYTLS_VERBOSE}" ] && warn_die "Unknown option: ${opt}"
		fi
	;;
	esac

	# fatal error when no value was provided
	if [ ! $empty_ok ] && { [ "${val}" = "${1}" ] || [ -z "${val}" ]; }; then
		warn_die "Missing value to option: ${opt}"
	fi
	shift
done

# Dependencies
deps

# Report and die on fatal warnings
warn_die

# Update log message
update_status "CN:${X509_0_CN}"

# Set Client certificate serial number from Openvpn env
client_serial="$(format_number "${tls_serial_hex_0}")"

# Verify Client certificate serial number
[ -z "${client_serial}" ] && {
	help_note="Openvpn failed to pass a client serial number"
	die "NO CLIENT SERIAL" 8
	}

# easytls client metadata file
generic_metadata_file="${EASYTLS_tmp_dir}/TCV2.${EASYTLS_srv_pid}"
client_metadata_file="${EASYTLS_tmp_dir}/${client_serial}.${EASYTLS_srv_pid}"

# --tls-verify output to --client-connect
generic_ext_md_file="${generic_metadata_file}-${untrusted_ip}-${untrusted_port}"
client_ext_md_file="${client_metadata_file}-${untrusted_ip}-${untrusted_port}"

# Check for kill signal
if [ -f "${EASYTLS_KILL_FILE}" ] && \
	"${EASYTLS_GREP}" -q "${client_serial}" "${EASYTLS_KILL_FILE}"
then
	# Kill client
	fail_and_exit "KILL_CLIENT" 5
fi

# Verify client_ext_md_file
if [ -f "${client_ext_md_file}" ]
then
	# Client cert serial matches
	update_status "X509 serial matched"
else
	# cert serial does not match - ALWAYS fail
	fail_and_exit "CLIENT X509 SERIAL MISMATCH" 7
fi

# Set only for NO keyed hwaddr
# Old field
if "${EASYTLS_GREP}" -q '[[:blank:]]000000000000$' "${client_ext_md_file}"
then
	key_hwaddr_missing=1
fi
# New field
if "${EASYTLS_GREP}" -q '=000000000000=$' "${client_ext_md_file}"
then
	key_hwaddr_missing=1
fi

# If keyed hwaddr is required and missing then fail - No exceptions
[ $key_hwaddr_required ] && [ $key_hwaddr_missing ] && \
	fail_and_exit "KEYED HWADDR REQUIRED BUT NOT KEYED" 4

# Set hwaddr from Openvpn env
# This is not a dep. different clients may not push-peer-info
push_hwaddr="$(format_number "${IV_HWADDR}")"
[ -z "${push_hwaddr}" ] && push_hwaddr_missing=1

# If pushed hwaddr is required and missing then fail - No exceptions
[ $push_hwaddr_required ] && [ $push_hwaddr_missing ] && \
	fail_and_exit "PUSHED HWADDR REQUIRED BUT NOT PUSHED" 3

# Verify hwaddr
if [ $key_hwaddr_missing ]
then
	# No keyed hwaddr
	update_status "Key is not locked to hwaddr"
	connection_allowed
else
	# key has a hwaddr
	if [ $push_hwaddr_missing ]
	then
		# push_hwaddr_missing and allow_no_check
		if [ $allow_no_check ]
		then
			update_status "hwaddr not pushed and not required"
			connection_allowed
		else
			# push_hwaddr_missing NOT allow_no_check
			fail_and_exit "PUSHED HWADDR REQUIRED BUT NOT PUSHED" 3
		fi
	else
		# hwaddr is pushed
		if "${EASYTLS_GREP}" -q "+${push_hwaddr}+" "${client_ext_md_file}"
		then
			# MATCH!
			update_status "hwaddr ${push_hwaddr} pushed and matched"
			connection_allowed
		else
			# push does not match key hwaddr
			failure_msg="Key does not match pushed hwaddr: ${push_hwaddr}"
			fail_and_exit "HWADDR MISMATCH" 2
		fi
	fi
fi

# Any failure_msg means fail_and_exit
[ -n "${failure_msg}" ] && fail_and_exit "NEIN: ${failure_msg}" 9

# For DUBUG
[ "${FORCE_ABSOLUTE_FAIL}" ] && \
	absolute_fail=1 && failure_msg="FORCE_ABSOLUTE_FAIL"

# There is only one way out of this...
if [ $absolute_fail -eq 0 ]
then
	# All is well
	verbose_print "<EXOK> ${status_msg}"
	[ $EASYTLS_FOR_WINDOWS ] && "${EASYTLS_PRINTF}" "%s\n" \
		"${status_msg}" > "${EASYTLS_WLOG}"
	exit 0
fi

# Otherwise
fail_and_exit "ABSOLUTE FAIL" 9
