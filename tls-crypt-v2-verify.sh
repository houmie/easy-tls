#!/bin/sh

# Copyright - negotiable
copyright ()
{
cat << VERBATUM_COPYRIGHT_HEADER_INCLUDE_NEGOTIABLE
# tls-crypt-v2-verify.sh -- Do simple magic
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
# Verify CA fingerprint
# Verify client certificate serial number against certificate revokation list
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
	metadata_client_CN="$(fn_metadata_client_CN)"

	if [ $TLS_CRYPT_V2_VERIFY_VERBOSE ]
	then
		printf "%s " "$tls_crypt_v2_verify_msg"
		[ -z "$success_msg" ] || printf "%s " "$success_msg"
		printf "%s\n%s\n" "$failure_msg $metadata_client_CN" "$1"

		printf "%s\n" \
			"* ==> metadata  local: $local_metadata_version"

		printf "%s\n" \
			"* ==> metadata remote: $remote_metadata_version"

		[ $TLS_CRYPT_V2_VERIFY_CG ] && printf "%s\n" \
			"* ==> custom_group  local: $TLS_CRYPT_V2_VERIFY_CG"

		[ $TLS_CRYPT_V2_VERIFY_CG ] && printf "%s\n" \
			"* ==> custom_group remote: $metadata_custom_group"

		printf "%s\n" \
			"* ==> CA Fingerprint  local: $local_ca_fingerprint"

		printf "%s\n" \
			"* ==> CA Fingerprint remote: $metadata_ca_fingerprint"

		printf "%s\n" \
			"* ==> Client serial remote: $metadata_client_cert_serno"

		printf "%s\n" \
			"* ==> Client CN     remote: $metadata_client_CN"

		[ $2 -eq 1 ] && printf "%s\n" \
			"* ==> Client serial status: revoked"

		[ -n "$help_note" ] && printf "%s\n" "$help_note"

		printf "%s\n" "https://github.com/TinCanTech/easy-tls"
	else
		printf "%s %s %s %s\n" "$tls_crypt_v2_verify_msg" \
			"$success_msg" "$failure_msg" "$metadata_client_CN"
	fi
	exit "${2:-254}"
} # => fail_and_exit ()

# Help
help_text ()
{
	help_msg='
  tls-crypt-v2-verify.sh

  This script is intended to be used by tls-crypt-v2 client keys
  generated by EasyTLS.  See: https://github.com/TinCanTech/easy-tls

  Options:
  help|-h|--help      This help text.
  -v|--verbose        Be a little more verbose at run time (Not Windows).
  -c|--ca <path>      Path to CA *Required*
  --verify-via-ca)    Verify client serial number status via `openssl ca`
                      NOT RECOMMENDED
                      The recommended method to verify client serial number
                      status is via `openssl crl` (This is the Default).
  -g|--custom-group=<GROUP>
                      Also verify the client metadata against a custom group.
                      The custom group can be appended when EasyTLS generates
                      the tls-crypt-v2 client key by using:
                      easytls --custom-group=XYZ build-tls-crypt-v2-client
                      XYZ MUST be a single alphanumerical word with NO spaces.

  Exit codes:
  0   - Allow connection, Client key has passed all tests.
  1   - Disallow connection, client key has passed all tests but is REVOKED.
  2   - Disallow connection, serial number is disabled.
  3   - Disallow connection, local/remote CA fingerprints do not match.
  4   - Disallow connection, local/remote Custom Groups do not match.
  5   - Disallow connection, invalid metadata_version_xx field.
  9   - BUG Disallow connection, general script failure.
  11  - ERROR Disallow connection, client key has invalid serial number.
  12  - ERROR Disallow connection, missing remote CA fingerprint.
  13  - ERROR Disallow connection, missing local CA fingerprint. (Unlucky)
  21  - USER ERROR Disallow connection, options error.
  22  - USER ERROR Disallow connection, failed to set --ca <path> *Required*.
  23  - USER ERROR Disallow connection, missing CA certificate.
  24  - USER ERROR Disallow connection, missing CRL file.
  25  - USER ERROR Disallow connection, missing index.txt.
  26  - USER ERROR Disallow connection, missing safessl-easyrsa.cnf.
  27  - USER ERROR Disallow connection, missing EasyTLS disabled list.
  28  - USER ERROR Disallow connection, missing openvpn server metadata_file.
  121 - BUG Disallow connection, client serial number is not in CA database.
  122 - BUG Disallow connection, failed to verify CRL.
  123 - BUG Disallow connection, failed to verify CA.
  127 - BUG Disallow connection, duplicate serial number in CA database. !?
  253 - Disallow connection, exit code when --help is called.
  254 - BUG Disallow connection, fail_and_exit() exited with default error code.
  255 - BUG Disallow connection, die() exited with default error code.
'
	printf "%s\n" "$help_msg"

	# For secrity, --help must exit with an error
	exit 253
}

# Verify CA
verify_ca ()
{
	openssl x509 -in "$ca_cert" -noout
}

# CA Local fingerprint
# space to underscore
fn_local_ca_fingerprint ()
{
	openssl x509 -in "$ca_cert" -noout -fingerprint | sed "s/\ /\_/g"
}

# Extract metadata version from client tls-crypt-v2 key metadata
fn_metadata_version ()
{
	awk '{print $1}' "$openvpn_metadata_file"
}

# Extract CA fingerprint from client tls-crypt-v2 key metadata
fn_metadata_ca_fingerprint ()
{
	awk '{print $2}' "$openvpn_metadata_file"
}

# Extract client cert serial number from client tls-crypt-v2 key metadata
fn_metadata_client_cert_serno ()
{
	awk '{print $3}' "$openvpn_metadata_file"
}

# Extract client name appendage from client tls-crypt-v2 key metadata
fn_metadata_client_CN ()
{
	awk '{print $4}' "$openvpn_metadata_file"
}

# Extract custom metadata appendage from client tls-crypt-v2 key metadata
fn_metadata_custom_group ()
{
	awk '{print $5}' "$openvpn_metadata_file"
}

# Requirements to verify a valid client cert serial number
verify_metadata_client_serial_number ()
{
	# Do we have a serial number
	[ -z "$metadata_client_cert_serno" ] && {
		failure_msg="Missing: Client serial number"
		fail_and_exit "SERIAL_NUMBER_MISSING" 11
		}

	# Hex only accepted
	serial_chars="$(allow_hex_only)"
	[ $serial_chars -eq 0 ] || {
		failure_msg="Invalid: Client serial number"
		fail_and_exit "SERIAL_NUMBER_INVALID" 11
		}
}

# Drop all non-hex chars from serial number and count the rest
allow_hex_only ()
{
	printf '%s' "$metadata_client_cert_serno"|grep -c '[^0123456789ABCDEF]'
}

# Check metadata client certificate serial number against disabled list
verify_serial_number_not_disabled ()
{
	# Search the disabled_list for client serial number
	client_disabled="$(fn_search_disabled_list)"
	case $client_disabled in
	0)
		# Client is not disabled
		return 0
	;;
	*)
		# Client is disabled
		insert_msg="client serial number is disabled:"
		failure_msg="$insert_msg $metadata_client_cert_serno"
		return 1
	;;
	esac

	# Otherwise fail
	help_note="Check your disabled list: $disabled_list"
	insert_msg="client serial number failed disabled test:"
	failure_msg="$insert_msg $metadata_client_cert_serno"
	return 1
}

# Search disabled list for client serial number
fn_search_disabled_list ()
{
	client_CN="$(fn_metadata_client_CN)"
	grep -c "^${metadata_client_cert_serno}[[:blank:]]${client_CN}$" \
		"$disabled_list"
}

# Verify CRL
verify_crl ()
{
	openssl crl -in "$crl_pem" -noout
}

# Decode CRL
fn_read_crl ()
{
	openssl crl -in "$crl_pem" -noout -text
}

# Search CRL for client cert serial number
fn_search_crl ()
{
	printf "%s\n" "$crl_text" | grep -c \
		"^[[:blank:]]*Serial Number: $metadata_client_cert_serno$"
}

# Final check: Search index.txt for client cert serial number
fn_search_index ()
{
	grep -c "^V.*[[:blank:]]${metadata_client_cert_serno}[[:blank:]].*$" \
		"$index_txt"
}

# Check metadata client certificate serial number against CRL
serial_status_via_crl ()
{
	client_cert_revoked="$(fn_search_crl)"
	case $client_cert_revoked in
	0)
		# Final check: Is this serial in index.txt
		case "$(fn_search_index)" in
		0)
		failure_msg="Serial number is not in the CA database:"
		fail_and_exit "SERIAL_NUMBER_UNKNOWN" 121
		;;
		1)
		client_passed_all_tests_connection_allowed
		;;
		*)
		die "Duplicate serial numbers: $metadata_client_cert_serno" 127
		;;
		esac
	;;
	1)
		client_passed_all_tests_certificate_revoked
	;;
	*)
		insert_msg="Duplicate serial numbers detected: "
		failure_msg="$insert_msg $metadata_client_cert_serno"
		die "Duplicate serial numbers: $metadata_client_cert_serno" 127
	;;
	esac
}

# This is the only way to connect
client_passed_all_tests_connection_allowed ()
{
	metadata_client_CN="$(fn_metadata_client_CN)"
	insert_msg="Client certificate is recognised and not revoked:"
	success_msg="$success_msg $insert_msg $metadata_client_cert_serno"
	success_msg="$success_msg $metadata_client_CN"
	absolute_fail=0
}

# This is the only way to fail for Revokation
client_passed_all_tests_certificate_revoked ()
{
	insert_msg="Client certificate is revoked:"
	failure_msg="$insert_msg $metadata_client_cert_serno"
	fail_and_exit "REVOKED" 1
}

# Check metadata client certificate serial number against CA
serial_status_via_ca ()
{
	# This is non-functional until openssl is fixed
	verify_openssl_serial_status

	# Get serial status via CA
	client_cert_serno_status="$(openssl_serial_status)"

	# Format serial status
	client_cert_serno_status="$(capture_serial_status)"
	client_cert_serno_status="${client_cert_serno_status% *}"
	client_cert_serno_status="${client_cert_serno_status##*=}"

	# Considering what has to be done, I don't like this
	case "$client_cert_serno_status" in
	Valid)
		client_passed_all_tests_connection_allowed
	;;
	Revoked)
		client_passed_all_tests_certificate_revoked
	;;
	*)
		die "Serial status via CA has broken" 9
	;;
	esac
}

# Use openssl to return certificate serial number status
openssl_serial_status ()
{
	# openssl appears to always exit with error - but here I do not care
	openssl ca -cert "$ca_cert" -config "$openssl_cnf" \
		-status "$metadata_client_cert_serno" 2>&1
}

# Capture serial status
capture_serial_status ()
{
	printf "%s\n" "$client_cert_serno_status" | grep '^.*=.*$'
}

# Verify openssl serial status returns ok
verify_openssl_serial_status ()
{
	return 0 # Disable this `return` if you want to test
	# openssl appears to always exit with error - have not solved this
	openssl ca -cert "$ca_cert" -config "$openssl_cnf" \
		-status "$metadata_client_cert_serno" || \
		die "openssl returned an error exit code" 101

# This is why I am not using CA, from `man 1 ca`
: << MAN_OPENSSL_CA
WARNINGS
       The ca command is quirky and at times downright unfriendly.

       The ca utility was originally meant as an example of how to do things
       in a CA. It was not supposed to be used as a full blown CA itself:
       nevertheless some people are using it for this purpose.

       The ca command is effectively a single user command: no locking is 
       done on the various files and attempts to run more than one ca command
       on the same database can have unpredictable results.
MAN_OPENSSL_CA
# This script ONLY reads, .:  I am hoping for better than 'unpredictable' ;-)
}

# Initialise
init ()
{
	# Fail by design
	absolute_fail=1

	# metadata version
	local_metadata_version="metadata_version_easytls_A4"

	# From openvpn server
	openvpn_metadata_file="$metadata_file"

	# Log message
	tls_crypt_v2_verify_msg="* TLS-crypt-v2-verify ==>"

	# Test certificate Valid/Revoked by CRL not CA
	test_method=1
}

# Dependancies
deps ()
{
	# CA_DIR MUST be set with option: -c|--ca
	[ -d "$CA_DIR" ] || die "Path to CA directory is required, see help" 22

	# CA required files
	ca_cert="$CA_DIR/ca.crt"
	crl_pem="$CA_DIR/crl.pem"
	index_txt="$CA_DIR/index.txt"
	openssl_cnf="$CA_DIR/safessl-easyrsa.cnf"
	disabled_list="$CA_DIR/easytls/easytls-disabled.txt"

	# Ensure we have all the necessary files
	help_note="This script requires an EasyRSA generated CA."
	[ -f "$ca_cert" ] || die "Missing CA certificate: $ca_cert" 23

	help_note="This script requires an EasyRSA generated CRL."
	[ -f "$crl_pem" ] || die "Missing CRL: $crl_pem" 24

	help_note="This script requires an EasyRSA generated DB."
	[ -f "$index_txt" ] || die "Missing index.txt: $index_txt" 25

	help_note="This script requires an EasyRSA generated PKI."
	[ -f "$openssl_cnf" ] || die "Missing openssl config: $openssl_cnf" 26

	help_note="This script requires an EasyTLS generated disabled_list."
	[ -f "$disabled_list" ] || \
		die "Missing disabled list: $disabled_list" 27

	# `metadata_file` must be set by openvpn
	help_note="This script can ONLY be used by a running openvpn server."
	[ -f "$openvpn_metadata_file" ] || \
		die "Missing: openvpn_metadata_file: $openvpn_metadata_file" 28
	unset help_note
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
	-c|--ca)
		CA_DIR="$val"
	;;
	--verify-via-ca)
		# This is only included for review
		empty_ok=1
		tls_crypt_v2_verify_msg="* TLS-crypt-v2-verify (ca) ==>"
		test_method=2
	;;
	-g|--custom-group)
		TLS_CRYPT_V2_VERIFY_CG="$val"
	;;
	*)
		die "Unknown option: $1" 253
	;;
	esac

	# fatal error when no value was provided
	if [ ! $empty_ok ] && { [ "$val" = "$1" ] || [ -z "$val" ]; }; then
		die "Missing value to option: $opt" 21
	fi

	shift
done


# Dependancies
deps


# Metadata Version
	remote_metadata_version="$(fn_metadata_version)"
	case $remote_metadata_version in
	"$local_metadata_version")
		# metadata_version_easytls_XX is correct
		success_msg="$remote_metadata_version ==>"
	;;
	*)
		if [ -z "$remote_metadata_version" ]
		then
			insert_msg="metadata version is missing."
		else
			insert_msg="metadata version is not recognised:"
		fi
		failure_msg="$insert_msg $remote_metadata_version"
		fail_and_exit "METADATA_VERSION" 5
	;;
	esac


# Metadata custom_group
	if [ -n "$TLS_CRYPT_V2_VERIFY_CG" ]
	then
		metadata_custom_group="$(fn_metadata_custom_group)"
		if [ "$metadata_custom_group" = "$TLS_CRYPT_V2_VERIFY_CG" ]
		then
			# Custom group is correct
			insert_msg="custom_group $metadata_custom_group OK ==>"
			success_msg="$success_msg $insert_msg"
		else
			insert_msg="metadata custom_group is not correct:"
			[ -z "$metadata_custom_group" ] && \
				insert_msg="metadata custom_group is missing"

			failure_msg="$insert_msg $metadata_custom_group"
			fail_and_exit "METADATA_CUSTOM_GROUP" 4
		fi
	fi


# Client certificate serial number

	# Collect client certificate serial number from tls-crypt-v2 metadata
	metadata_client_cert_serno="$(fn_metadata_client_cert_serno)"

	# Client serial number requirements
	verify_metadata_client_serial_number


# Disabled list check

	# Check serial number is not disabled
	verify_serial_number_not_disabled || fail_and_exit "CLIENT_DISABLED" 2


# CA Fingerprint

	# Verify CA
	verify_ca || die "Bad CA $ca_cert" 123

	# Capture CA fingerprint
	# Format to one contiguous string (Same as encoded metadata)
	local_ca_fingerprint="$(fn_local_ca_fingerprint)"

	# local_ca_fingerprint is required
	[ -z "$local_ca_fingerprint" ] && {
		failure_msg="Missing: local CA fingerprint"
		fail_and_exit "LOCAL_FINGER_PRINT" 13
		}

	# Collect CA fingerprint from tls-crypt-v2 metadata
	metadata_ca_fingerprint="$(fn_metadata_ca_fingerprint)"

	# metadata_ca_fingerprint is required
	[ -z "$metadata_ca_fingerprint" ] && {
		failure_msg="Missing: remote CA fingerprint"
		fail_and_exit "REMOTE_FINGER_PRINT" 12
		}


# Check metadata CA fingerprint against local CA fingerprint
if [ "$local_ca_fingerprint" = "$metadata_ca_fingerprint" ]
then
	success_msg="$success_msg CA Fingerprint OK ==>"
else
	failure_msg="CA Fingerprint mismatch"
	fail_and_exit "FINGER_PRINT_MISMATCH" 3
fi


# Certificate Revokation List

	# Verify CRL
	verify_crl || die "Bad CRL: $crl_pem" 122

	# Capture CRL
	crl_text="$(fn_read_crl)"


# Verify serial status by method 1 or 2

# Default test_method=1
test_method=${test_method:-1}

case $test_method in
	1)
		# Method 1
		# Check metadata client certificate serial number against CRL
		serial_status_via_crl
	;;
	2)
		# Method 2
		# Check metadata client certificate serial number against CA

		# Due to openssl being "what it is", it is not possible to
		# reliably verify the 'openssl ca $cmd'
		serial_status_via_ca
	;;
	*)
		die "Unknown method for verify: $test_method" 9
	;;
esac

# failure_msg means fail_and_exit
[ "$failure_msg" ] && fail_and_exit "NEIN" 9

# There is only one way out of this...
[ $absolute_fail -eq 0 ] || fail_and_exit "ABSOLUTE_FAIL" 9

# All is well
[ $TLS_CRYPT_V2_VERIFY_VERBOSE ] && \
	printf "%s\n" "<EXOK> $tls_crypt_v2_verify_msg $success_msg"

exit 0
