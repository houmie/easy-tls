#!/bin/sh

# Copyright - negotiable
copyright ()
{
: << VERBATUM_COPYRIGHT_HEADER_INCLUDE_NEGOTIABLE
# easytls-verify.sh -- Do simple magic
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
  easytls-verify.sh

  This script is intended to be used by tls-crypt-v2 client keys
  generated by EasyTLS.  See: https://github.com/TinCanTech/easy-tls

  Options:
  help|-h|--help         This help text.
  -v|--verbose           Be a lot more verbose at run time (Not Windows).
  -c|--ca=<DIR>          Path to CA *REQUIRED*
  -z|--no-ca             Run in No CA mode. Still requires --ca=<PATH>
  -k|kill-client)        Use easytls-client-connect script to kill client.
                         Killing a client can only be done once a client has
                         connected, so a failed connection must roll-over, then
                         easytls-client-connect.sh immediately kills the client.
  -m|--ignore-mismatch   Ignore tlskey-x509 vs openvpn-x509 mismatch.
  -p|--ignore-expired    Ignore expiry and allow connection of expired clients
  -q|--ignore-require    Ignore TLS-Crypt-V2 key requirement
  -r|--ignore-revoked    Ignore revocation and allow connection of revoked clients
                         (Only works in full PKI mode)
  -x|--x509              Check X509 certificate validity
                         (Only works in full PKI mode)
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
  2   - Disallow connection, Client cert expired.
  3   - Disallow connection, Client cert revoked.
  4   - Disallow connection, Client cert not recognised.
  5   - Disallow connection, Client cert should have TLS-Crypt-v2 key.
  6   - Disallow connection, TLS-key X509 serial and Openvpn X509 serial mismatch.
  9   - Disallow connection, unexpected failure. (BUG)
  11  - Disallow connection, missing X509 client cert serial. (BUG)
  12  - Disallow connection, CA PKI dir not defined. (REQUIRED)
  13  - Disallow connection, CA cert not found.
  14  - Disallow connection, index.txt not found.
  15  - Disallow connection, Script requires --tls-export-cert
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

  111 - BUG Disallow connection, required trusted client does not exist
  252 - Disallow connection, script access permission.
  253 - Disallow connection, exit code when --help is called.
  254 - BUG Disallow connection, fail_and_exit() exited with default error code.
  255 - BUG Disallow connection, die() exited with default error code.
"
	print "${help_msg}"

	# For secrity, --help must exit with an error
	exit 253
} # => help_text ()

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
	print "${failure_msg}"
	print "${1}"

	[ $EASYTLS_FOR_WINDOWS ] && "${EASYTLS_PRINTF}" "%s %s %s %s\n" \
		"<FAIL> ${status_msg}" "${failure_msg}" "${1}" \
			"kill_client: ${kill_client:-0}" > "${EASYTLS_WLOG}"

	[ $kill_client ] && {
		"${EASYTLS_PRINTF}" "%s\n%s\n%s\n%s\n" "${client_serial}" \
			"${kill_client_serial}" "${g_md_serial}" "${c_md_serial}" \
			> "${EASYTLS_KILL_FILE}"
		exit 0
		}

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
		"${g_md_x509_serial_md_file}" \

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

# Log warnings
warn_log ()
{
	if [ -n "${1}" ]
	then
		warn_msg="${warn_msg}
${1}"
	else
		[ -z "${warn_msg}" ] || verbose_print "${warn_msg}"
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
	absolute_fail=0
	update_status "connection allowed"
}

# Create stage-1 file
create_stage1_file ()
{
	if [ -f "${stage1_file}" ]
	then
		print "*** Stage-1 file exists"
		exit 96
	else
		"${EASYTLS_PRINTF}" '%s' '1' > "${stage1_file}" || return 1
		update_status "Stage-1 file created"
	fi
}

# Create stage-1 file
delete_stage1_file ()
{
	if [ -f "${stage1_file}" ]
	then
		"${EASYTLS_RM}" "${stage1_file}" || return 1
		update_status "Stage-1 file deleted"
	else
		print "*** Stage-1 file missing"
		exit 97
	fi
}

# Initialise
init ()
{
	# Fail by design
	absolute_fail=1

	# Defaults
	EASYTLS_srv_pid=$PPID

	# Log message
	status_msg="* EasyTLS-verify"

	# Default stale-metadata-output-file time-out
	#stale_sec=30

	# Identify Windows
	EASYRSA_KSH='@(#)MIRBSD KSH R39-w32-beta14 $Date: 2013/06/28 21:28:57 $'
	[ "${KSH_VERSION}" = "${EASYRSA_KSH}" ] && EASYTLS_FOR_WINDOWS=1

	# Required binaries
	EASYTLS_OPENSSL='openssl'
	EASYTLS_CAT='cat'
	EASYTLS_CP='cp'
	EASYTLS_DATE='date'
	EASYTLS_GREP='grep'
	EASYTLS_MV='mv'
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
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_CP}.exe" ] || exit 72
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_DATE}.exe" ] || exit 66
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_GREP}.exe" ] || exit 67
		[ -f "${EASYTLS_ersabin_dir}/${EASYTLS_MV}.exe" ] || exit 71
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
	[ -d "${EASYTLS_tmp_dir}" ] || {
		help_note="You must create the temporary directory."
		die "Temporary dirictory does not exist ${EASYTLS_tmp_dir}" 60
		}

	# CA_dir MUST be set with option: -c|--ca
	[ -d "${CA_dir}" ] || {
		help_note="This script requires an EasyRSA generated PKI."
		die "Path to CA directory is required, see help" 12
		}

	# Easy-TLS required files
	TLS_dir="${CA_dir}/easytls/data"
	#disabled_list="${TLS_dir}/easytls-disabled-list.txt"
	#tlskey_serial_index="${TLS_dir}/easytls-key-index.txt"

	# Check TLS files
	[ -d "${TLS_dir}" ] || {
		help_note="Use './easytls init <no-ca>"
		die "Missing EasyTLS dir: ${TLS_dir}"
		}

	# CA required files
	ca_cert="${CA_dir}/ca.crt"
	index_txt="${CA_dir}/index.txt"

	if [ $EASYTLS_NO_CA ]
	then
		# Do not need CA cert
		:
	else
		# Ensure we have all the necessary files
		[ -f "${ca_cert}" ] || {
			help_note="This script requires an EasyRSA generated CA."
			die "Missing CA certificate: ${ca_cert}" 13
			}
		[ -f "${index_txt}" ] || {
			help_note="This script requires an EasyRSA generated DB."
			die "Missing index.txt: ${index_txt}" 14
			}
	fi

	# Check for peer_cert
	[ -f "${peer_cert}" ] || {
		help_note="This script requires Openvpn --tls-export-cert"
		die "Missing peer_cert variable or file: ${peer_cert}" 15
		}

	# Windows log
	EASYTLS_WLOG="${EASYTLS_tmp_dir}/easytls-tv.log.${EASYTLS_srv_pid}"

	# Kill client file
	EASYTLS_KILL_FILE="${EASYTLS_tmp_dir}/kill-client.${EASYTLS_srv_pid}"
} # => deps ()

# generic metadata_string into variables
generic_metadata_string_to_vars ()
{
	g_tlskey_serial="${1%%-*}"
	g_md_seed="${metadata_string#*-}"
	#md_padding="${md_seed%%--*}"
	g_md_easytls_ver="${1#*--}"
	g_md_easytls="${md_easytls_ver%-*.*}"

	g_md_identity="${2%%-*}"
	#md_srv_name="${2##*-}"

	g_md_serial="${3}"
	g_md_date="${4}"
	g_md_custom_g="${5}"
	g_md_name="${6}"
	g_md_subkey="${7}"
	g_md_opt="${8}"
	g_md_hwadds="${9}"
} # => metadata_string_to_vars ()

# client metadata_string into variables
client_metadata_string_to_vars ()
{
	c_tlskey_serial="${1%%-*}"
	c_md_seed="${metadata_string#*-}"
	#md_padding="${md_seed%%--*}"
	c_md_easytls_ver="${1#*--}"
	c_md_easytls="${md_easytls_ver%-*.*}"

	c_md_identity="${2%%-*}"
	#md_srv_name="${2##*-}"

	c_md_serial="${3}"
	c_md_date="${4}"
	c_md_custom_g="${5}"
	c_md_name="${6}"
	c_md_subkey="${7}"
	c_md_opt="${8}"
	c_md_hwadds="${9}"
} # => metadata_string_to_vars ()

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
	-c|--ca)
		CA_dir="${val}"
	;;
	-z|--no-ca)
		empty_ok=1
		EASYTLS_NO_CA=1
	;;
	-x|--x509)
		empty_ok=1
		x509_check=1
	;;
	-m|ignore-mismatch) # tlskey-x509 does not match openvpn-x509
		empty_ok=1
		ignore_x509_mismatch=1
	;;
	-k|kill-client) # Use client-connect to kill client
		empty_ok=1
		kill_client=1
	;;
	-p|--ignore-expired)
		empty_ok=1
		ignore_expired=1
	;;
	-q|--ignore-required)
		empty_ok=1
		ignore_required=1
	;;
	-r|--ignore-revoked)
		empty_ok=1
		ignore_revoked=1
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
	0)
		empty_ok=1
		EASYTLS_cert_depth="0"
	;;
	1)
		# DISABLE CA verify
		empty_ok=1
		EASYTLS_cert_depth="1"
	;;
	CN)
		empty_ok=1
		EASYTLS_CN="${val}" # Currently not used
	;;
	*)
		empty_ok=1
		if [ -f "${opt}" ]
		then
			# Do not need this in the log but keep it here for reference
			#[ $EASYTLS_VERBOSE ] && warn_log "Ignoring temp file: $opt"
			:
		else
			[ "${EASYTLS_VERBOSE}" ] && warn_log "Ignoring unknown option: ${opt}"
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

# Report option warnings
warn_log

# Update log message
case ${EASYTLS_cert_depth} in
1)	update_status "CN:${X509_1_CN}" ;;
0)	update_status "CN:${X509_0_CN}" ;;
*)	die "Unsupported certificate depth: ${EASYTLS_cert_depth}" ;;
esac

# TLS verify checks

# Work around for double call of --tls-verify in peer-fingerprint mode
stage1_file="${EASYTLS_tmp_dir}/${EASYTLS_srv_pid}"
stage1_file="${stage1_file}-${untrusted_ip}-${untrusted_port}.stage-1"

if [ -f "${stage1_file}" ]
then
	# Remove stage-1 file, all metadata files are in place
	delete_stage1_file || die "Failed to remove stage-1 file" 252

	# Set Client certificate serial number from Openvpn env
	client_serial="$(format_number "${tls_serial_hex_0}")"

	# Verify Client certificate serial number
	[ -n "${client_serial}" ] || die "MISSING CLIENT CERTIFICATE SERIAL" 11

	# Load kill-client file
	if [ -f "${EASYTLS_KILL_FILE}" ]
	then
		kill_client_serial="$("${EASYTLS_CAT}" "${EASYTLS_KILL_FILE}")"
	fi

	# ----------
	# generic metadata file
	generic_metadata_file="${EASYTLS_tmp_dir}/TCV2.${EASYTLS_srv_pid}"

	# extended generic metadata file
	generic_ext_md_file="${generic_metadata_file}-${untrusted_ip}-${untrusted_port}"

	# generic trusted file - For reneg - float does not require any script
	generic_trusted_md_file="${generic_metadata_file}-${trusted_ip}-${trusted_port}"

	# TLS-Crypt-V2 key flag
	g_tls_crypt_v2=1

	# Move generic to generic-ext
	# If these file-names match then this is a renegotiation
	if [ "${generic_ext_md_file}" = "${generic_trusted_md_file}" ]
	then
		# Renegotiation only
		reneg_only=1
		#unset g_tls_crypt_v2
		update_status "Reneg ok(g1)"

	elif [ -f "${generic_metadata_file}" ] && [ ! -f "${generic_ext_md_file}" ]
	then
		# Initial connection only - Always succeeds
		"${EASYTLS_MV}" "${generic_metadata_file}" "${generic_ext_md_file}" || \
			die "mv generic_metadata_file failed"
		update_status "generic_ext_md_file READY"

	elif [ ! -f "${generic_metadata_file}" ] && [ -f "${generic_ext_md_file}" ]
	then
		# Something else is wrong - maybe a connection over-lap
		# Have not managed to trigger this situation .. yet
		# Which is probably a good indicator that the script is sound
		die "problem with generic files(g1)"

	elif [ ! -f "${generic_metadata_file}" ] && [ ! -f "${generic_ext_md_file}" ]
	then
		# No generic files means --tls-auth/crypt v1 only and not reneg
		unset g_tls_crypt_v2

	else
		# Something else is wrong - maybe a connection over-lap
		# Have not managed to trigger this situation .. yet
		# Which is probably a good indicator that the script is sound
		die "Problem with temp files(g2)"
	fi

	if [ $g_tls_crypt_v2 ] && [ ! $reneg_only ]
	then
		# Get generic metadata_string
		metadata_string="$("${EASYTLS_CAT}" "${generic_ext_md_file}")"
		[ -n "${metadata_string}" ] || \
			fail_and_exit "failed to read generic_ext_md_file" 18
		# Populate generic metadata variables
		generic_metadata_string_to_vars $metadata_string
		[ -n "${g_tlskey_serial}" ] || \
			fail_and_exit "failed to set g_tlskey_serial" 19
		unset metadata_string
		update_status "generic metadata loaded"

	elif [ $g_tls_crypt_v2 ] && [ $reneg_only ]
	then
		update_status "Renegotiation ok(g2)"

	else
		# Must be TLS-auth/crypt-v1
		unset g_tls_crypt_v2
		update_status "TLS-Auth/Crypt(g1)"
	fi
	# ----------

	# generic metadata X509 serial file - not openvpn x509-serial
	g_md_x509_serial_md_file="${EASYTLS_tmp_dir}/${g_md_serial}.${EASYTLS_srv_pid}"

	# ----------
	# client metadata file
	client_metadata_file="${EASYTLS_tmp_dir}/${client_serial}.${EASYTLS_srv_pid}"

	# extended client metadata file
	client_ext_md_file="${client_metadata_file}-${untrusted_ip}-${untrusted_port}"

	# client trusted file - For reneg
	# float does not trigger any script
	client_trusted_md_file="${client_metadata_file}-${trusted_ip}-${trusted_port}"

	# TLS-Crypt-V2 key flag
	c_tls_crypt_v2=1

	# Move client to client-ext
	# If these file-names match then this is a renegotiation
	if [ "${client_ext_md_file}" = "${client_trusted_md_file}" ]
	then
		# Renegotiation
		reneg_only=1
		#unset c_tls_crypt_v2
		update_status "Renegotiation ok(c1)"

	elif [ -f "${client_metadata_file}" ] && [ ! -f "${client_ext_md_file}" ]
	then
		# Initial connection only - tlskey x509 match
		"${EASYTLS_MV}" "${client_metadata_file}" "${client_ext_md_file}" || \
			die "mv client_metadata_file failed"
		update_status "client_ext_md_file READY"

	elif [ ! -f "${client_metadata_file}" ] && [ -f "${client_ext_md_file}" ]
	then
		# Something else is wrong - maybe a connection over-lap
		# Have not managed to trigger this situation .. yet
		# Which is probably a good indicator that the script is sound
		die "problem with client files(c1)"

	elif [ ! -f "${client_metadata_file}" ] && [ ! -f "${client_ext_md_file}" ]
	then
		# Initial connection only - tlskey x509 mismatch
		# Or --tls-auth/crypt-v1
		if [ $g_tls_crypt_v2 ]
		then
			if [ $kill_client ]
			then
				kill_this_client=1
				update_status "Killing client(c1)"
			elif [ $ignore_x509_mismatch ]
			then
				update_status "Ignored tlskey X509 mismatch!(c1)"
			else
				failure_msg="TLS-key is being used by the wrong client certificate"
				fail_and_exit "TLSKEY_X509_SERIAL-OVPN_X509_SERIAL-MISMATCH*1" 6
			fi

			# Move generic file in place of the non-existant client_ext_md_file
			if [ -f "${g_md_x509_serial_md_file}" ]
			then
				"${EASYTLS_MV}" \
					"${g_md_x509_serial_md_file}" "${client_ext_md_file}" || \
						die "Failed to move g_md_x509_serial_md_file"
				update_status "g_md_x509_serial_md_file READY(generic)"
			else
				die "Failed to find g_md_x509_serial_md_file"
			fi

		else
			# This is correct behaviour for --tls-auth/crypt v1
			# Create a fake extended metadata file
			"${EASYTLS_PRINTF}" '%s' '=000000000000=' > "${client_ext_md_file}" || \
				die "Failed to create fake client_ext_md_file"
			c_tls_crypt_v1=1
			update_status "TLS-Auth/Crypt(c1)"
		fi

	else
		# Something else is wrong - maybe a connection over-lap
		# Have not managed to trigger this situation .. yet
		# Which is probably a good indicator that the script is sound
		die "problem with client files"
	fi

	if [ $c_tls_crypt_v2 ] && [ ! $reneg_only ] && [ ! $kill_this_client ]
	then
		# Get client metadata_string
		metadata_string="$("${EASYTLS_CAT}" "${client_ext_md_file}")"
		[ -n "${metadata_string}" ] || \
			fail_and_exit "failed to read client_ext_md_file" 18
		# Populate client metadata variables
		client_metadata_string_to_vars $metadata_string
		[ -n "${c_tlskey_serial}" ] || \
			fail_and_exit "failed to set c_tlskey_serial" 19
		unset metadata_string
		update_status "client_ext_md_file loaded"

	elif [ $c_tls_crypt_v2 ] && [ $reneg_only ] && [ ! $kill_this_client ]
	then
		update_status "Renegotiation ok(c2)"

	elif [ $c_tls_crypt_v1 ] && [ ! $kill_this_client ]
	then
		update_status "TLS-Auth/Crypt(c2)"

	elif [ $kill_this_client ]
	then
		update_status "Killing client(c2)"

	else
		# Something else is wrong - maybe a connection over-lap
		# Have not managed to trigger this situation .. yet
		# Which is probably a good indicator that the script is sound
		die "Unknown(c1)"
	fi
	# ----------

	# Checks for all
	if [ "${c_md_serial}" = "${client_serial}" ]
	then
		update_status "tlskey x509 matched"

	elif [ "${g_md_serial}" = "${client_serial}" ]
	then
		[ $ignore_x509_mismatch ] || {
			failure_msg="TLS-key is being used by the wrong client certificate"
			fail_and_exit "TLSKEY_X509_SERIAL-OVPN_X509_SERIAL-MISMATCH*2" 7
			}
		update_status "Ignored tlskey X509 mismatch!(a1)"

	elif [ $reneg_only ]
	then
		# Nothing more required
		:

	elif [ $c_tls_crypt_v1 ]
	then
		# Nothing more required
		:

	else
		# tls-key X509 serial does not match openvpn X509 serial
		if [ $ignore_x509_mismatch ]
		then
			update_status "Ignored tlskey X509 mismatch!(a2)"
		elif [ $kill_this_client ]
		then
			update_status "Kill client(c3)"
		else
			failure_msg="TLS-key is being used by the wrong client certificate"
			fail_and_exit "TLSKEY_X509_SERIAL-OVPN_X509_SERIAL-MISMATCH*3" 8
		fi
	fi

	if [ $EASYTLS_NO_CA ]
	then
	# BEGIN: No-CA checks

		# Certificate expire date
		expire_date=$(
			"${EASYTLS_OPENSSL}" x509 -in "${peer_cert}" -noout -enddate |
			"${EASYTLS_SED}" 's/^notAfter=//'
			)
		expire_date_sec=$("${EASYTLS_DATE}" -d "$expire_date" +%s)

		# Current date
		local_date_sec=$("${EASYTLS_DATE}" +%s)

		# Check for expire
		if [ ${expire_date_sec} -lt ${local_date_sec} ]
		then
			update_status "Certificate expired"
			[ $ignore_expired ] || \
				fail_and_exit "CLIENT CERTIFICATE IS EXPIRED" 2
			update_status "Ignored expiry"
		else
			update_status "Certificate is not expired"
		fi
	# END: No-CA checks

	else
	# BEGIN: CA checks

		# Check cert serial is known by index.txt
		serial="^.[[:blank:]]*[[:digit:]]*Z[[:blank:]]*${client_serial}[[:blank:]]"
		valids="^V[[:blank:]]*[[:digit:]]*Z[[:blank:]]*${client_serial}[[:blank:]]"
		if "${EASYTLS_GREP}" -q "${serial}" "${index_txt}"
		then
			if [ $x509_check ]
			then
				if "${EASYTLS_GREP}" -q "${valids}" "${index_txt}"
				then
					# Valid Cert serial found in PKI index.txt
					update_status "Valid Client cert serial"
				else
					[ $ignore_revoked ] || \
						fail_and_exit "CLIENT CERTIFICATE IS REVOKED" 3
					update_status "Ignored revocation"
				fi
			else
				# Cert serial found in PKI index.txt
				update_status "Recognised Client cert serial"
			fi
		else
			# Cert serial not found in PKI index.txt
			fail_and_exit "ALIEN CLIENT CERTIFICATE SERIAL" 4
		fi
	fi
	# END: CA checks

else
	# Create stage-1 file
	create_stage1_file || die "Failed to create stage-1 file" 251
fi # stage1_file

# Allow this connection
connection_allowed

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
		"<EXOK> ${status_msg}" > "${EASYTLS_WLOG}"
	[ $kill_this_client ] && "${EASYTLS_PRINTF}" "%s\n%s\n%s\n%s\n" \
		"${client_serial}" "${kill_client_serial}" \
		"${g_md_serial}" "${c_md_serial}" > "${EASYTLS_KILL_FILE}"
	exit 0
fi

# Otherwise
fail_and_exit "ABSOLUTE FAIL" 9
