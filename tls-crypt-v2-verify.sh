#!/bin/sh

# Copyright (C) 2020 Richard Bonhomme (Friday 13th of March 2020)
# https://github.com/TinCanTech
# tincanteksup@gmail.com
# All Rights reserved.
#
# This code is released under version 2 of the GNU GPL
# See LICENSE of this project for full licensing details.
#

# Verify CA fingerprint
# Verify client certificate serial number against certificate revokation list

# This is here to catch "print" statements
# Wrapper around printf - clobber print since it's not POSIX anyway
# shellcheck disable=SC1117
print() { "$printf_bin" "%s\n" "$1"; }

# Exit on error
die ()
{
	"$printf_bin" "\n%s\n" "ERROR: $1"
	"$printf_bin" "%s\n" "https://github.com/TinCanTech/easy-tls"
	exit "${2:-254}"
}

# Tls-crypt-v2-verify failure, not an error.
fail_and_exit ()
{
	if [ $TLS_CRYPT_V2_VERIFY_VERBOSE ]
	then
		"$printf_bin" "%s%s%s\n%s\n" "$tls_crypt_v2_verify_msg" \
			"$success_msg" "$failure_msg" "$1"

		"$printf_bin" "%s\n" "* ==> metadata_version: $metadata_version"

		[ $TLS_CRYPT_V2_VERIFY_CG ] && "$printf_bin" "%s\n" \
			"* ==> custom_group  local: $TLS_CRYPT_V2_VERIFY_CG"

		[ $TLS_CRYPT_V2_VERIFY_CG ] && "$printf_bin" "%s\n" \
			"* ==> custom_group remote: $metadata_custom_group"

		"$printf_bin" "%s\n" \
			"* ==> CA Fingerprint  local: $local_ca_fingerprint"

		"$printf_bin" "%s\n" \
			"* ==> CA Fingerprint remote: $metadata_ca_fingerprint"

		"$printf_bin" "%s\n" \
			"* ==> Client serial remote: $metadata_client_cert_serno"

		[ $2 -eq 1 ] && "$printf_bin" "%s\n" \
			"* ==> Client serial status: revoked"

		[ -n "$help_note" ] && "$printf_bin" "$help_note"
	else
		"$printf_bin" "%s%s%s\n" \
			"$tls_crypt_v2_verify_msg" "$success_msg" "$failure_msg"
	fi
	exit "${2:-1}"
}

# Help
help_text ()
{
	# Another Linux nuance, must use prinf here ?
	# As this will only be run be the user, so be it.
	help_msg='
  tls-crypt-v2-verify.sh

  This script is intended to be used by tls-crypt-v2 client files
  which have been generated by EasyTLS.

  Options:
  -h|-help|--help     This help text.
  -v|--verbose        Be a little more verbose at run time.
  -g|--custom-group   Also verify the client metadata against a custom group.
                      The custom group can be appended when EasyTLS generates
                      the tls-crypt-v2 client key by using:
                      easytls --custom-group=XYZ build-tls-crypt-v2-client
                      XYZ MUST be a single alphanumerical word with NO spaces.
'

	"$printf_bin" "%s\n" "$help_msg"

	exit 123
}

# Verify CA
verify_ca ()
{
	"$ssl_bin" x509 -in "$ca_cert" -noout
}

# CA Local fingerprint
# space to underscore
fn_local_ca_fingerprint ()
{
	"$ssl_bin" x509 -in "$ca_cert" -noout -fingerprint | "$sed_bin" "s/\ /\_/g"
}

# Extract metadata version from client tls-crypt-v2 key metadata
fn_metadata_version ()
{
	"$awk_bin" '{print $1}' "$openvpn_metadata_file"
}

# Extract CA fingerprint from client tls-crypt-v2 key metadata
fn_metadata_ca_fingerprint ()
{
	"$awk_bin" '{print $2}' "$openvpn_metadata_file"
}

# Extract client cert serial number from client tls-crypt-v2 key metadata
# And drop the 'serial='
fn_metadata_client_cert_serno ()
{
	"$awk_bin" '{print $3}' "$openvpn_metadata_file" | "$sed_bin" "s/^.*=//g"
}

# Extract custom metadata appendage from client tls-crypt-v2 key metadata
fn_metadata_custom_group ()
{
	"$awk_bin" '{print $4}' "$openvpn_metadata_file"
}

# Requirements to verify a valid client cert serial number
verify_metadata_client_serial_number ()
{
	# Do we have a serial number
	[ -z "$metadata_client_cert_serno" ] && fail_and_exit \
		"Missing: client certificate serial number" 2

	# Hex only accepted
	serial_chars="$(Allow_hex_only)"
	[ $serial_chars -eq 0 ] || fail_and_exit "Invalid serial number" 2

	if [ $allow_only_random_serno -eq 1 ]
	then
		help_note="Use randomised serial numbers in EasyRSA3"
		serial_length=${#metadata_client_cert_serno}
		[ $serial_length -eq 32 ] || \
			fail_and_exit "Invalid serial number length" 2
		unset help_note
	fi
}

# Drop all non-hex chars from serial number and count the rest
Allow_hex_only ()
{
	printf '%s' "$metadata_client_cert_serno" | grep -c '[^0123456789ABCDEF]'
}

# Verify CRL
verify_crl ()
{
	"$ssl_bin" crl -in "$crl_pem" -noout
}

# Decode CRL
fn_read_crl ()
{
	"$ssl_bin" crl -in "$crl_pem" -noout -text
}

# Search CRL for client cert serial number
fn_search_crl ()
{
	"$printf_bin" "%s\n" "$crl_text" | \
		"$grep_bin" -c "$metadata_client_cert_serno"
}

# Final check: Search index.txt for client cert serial number
fn_search_index ()
{
	"$grep_bin" -c "^V.*$metadata_client_cert_serno" "$index_txt"
}

# Check metadata client certificate serial number against CRL
serial_status_via_crl ()
{
	client_cert_revoked="$(fn_search_crl)"
	case $client_cert_revoked in
	0)
		# Final check: Is this serial in index.txt
		[ "$(fn_search_index)" -eq 1 ] || fail_and_exit \
			"Client certificate is not in the CA index database" 11

		insert_msg="Client certificate is recognised and not revoked:"
		success_msg="$success_msg $insert_msg $metadata_client_cert_serno"
		absolute_fail=0
	;;
	1)
		insert_msg="Client certificate is revoked:"
		failure_msg="$failure_msg $insert_msg $metadata_client_cert_serno"
		fail_and_exit "REVOKED" 1
	;;
	*)
		insert_msg="Duplicate serial numbers detected:"
		failure_msg="$failure_msg $insert_msg $metadata_client_cert_serno"
		die "Duplicate serial numbers: $metadata_client_cert_serno" 127
	;;
esac
}

# Check metadata client certificate serial number against CA
serial_status_via_ca ()
{
	# This does not return openssl output to variable
	# If you have a fix please make an issue and/or PR
	client_cert_serno_status="$(openssl_serial_status)"
	"$printf_bin" "%s\n" "client_cert_serno_status: $client_cert_serno_status"
	client_cert_serno_status="${client_cert_serno_status##*=}"
	case "$client_cert_serno_status" in
		Valid)		die "IMPOSSIBLE" 102 ;; # Valid ?
		Revoked)	die "REVOKED" 103 ;;
		*)		die "Serial status via CA is broken" 9 ;;
	esac
}

# Use openssl to return certificate serial number status
openssl_serial_status ()
{
	"$EASYTLS_OPENSSL" ca -cert "$ca_cert" -config "$openssl_cnf" \
		-status "$metadata_client_cert_serno"
}

# Verify openssl serial status returns ok
verify_openssl_serial_status ()
{
	return 0
	# Cannot defend an error here because openssl always returns 1
	"$EASYTLS_OPENSSL" ca -cert "$ca_cert" -config "$openssl_cnf" \
		-status "$metadata_client_cert_serno" || \
		die "openssl failed to return a useful exit code" 101

# I presume they don't want people to use CA so they broke it
# Which is why I will not use CA
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
}

# Initialise
init ()
{
	# Must set full paths for scripts in OpenVPN
	case $OS in
	Windows_NT)
		# Need these .exe's from easyrsa3 installation
		EASYRSA_DIR="c:/program files/openvpn/easyrsa3"
		grep_bin="$EASYRSA_DIR/bin/grep.exe"
		sed_bin="$EASYRSA_DIR/bin/sed.exe"
		cat_bin="$EASYRSA_DIR/bin/cat.exe"
		awk_bin="$EASYRSA_DIR/bin/awk.exe"
		printf_bin="$EASYRSA_DIR/bin/printf.exe"
		ssl_bin="$EASYRSA_DIR/bin/openssl.exe"
		ca_cert="$EASYRSA_DIR/pki/ca.crt"
		crl_pem="$EASYRSA_DIR/pki/crl.pem"
		index_txt="$EASYRSA_DIR/pki/index.txt"
		openssl_cnf="../pki/safessl-easyrsa.cnf"
		EASYTLS_OPENSSL="openssl"
	;;
	*)
		# Standard Linux binaries
		grep_bin="/bin/grep"
		sed_bin="/bin/sed"
		cat_bin="/bin/cat"
		awk_bin="/usr/bin/awk"
		printf_bin="/usr/bin/printf"
		ssl_bin="/usr/bin/openssl"
		ca_cert="../pki/ca.crt"
		crl_pem="../pki/crl.pem"
		index_txt="../pki/index.txt"
		openssl_cnf="../pki/safessl-easyrsa.cnf"
		EASYTLS_OPENSSL="openssl"
	;;
	esac

	# Fail by design
	absolute_fail=1

	# From openvpn server
	openvpn_metadata_file="$metadata_file"

	# Log message
	tls_crypt_v2_verify_msg="* TLS-crypt-v2-verify ==>"
	success_msg=""
	failure_msg=""

	# Verify client cert serno has 32 chars
	allow_only_random_serno=1
}

# deps
deps ()
{
	# Ensure we have all the necessary files
	[ -f "$grep_bin" ] || die "Missing: $grep_bin" 10
	[ -f "$sed_bin" ] || die "Missing: $sed_bin" 10
	[ -f "$cat_bin" ] || die "Missing: $cat_bin" 10
	[ -f "$awk_bin" ] || die "Missing: $awk_bin" 10
	[ -f "$printf_bin" ] || die "Missing: $printf_bin" 10
	[ -f "$ssl_bin" ] || die "Missing: $ssl_bin" 10
	[ -f "$ca_cert" ] || die "Missing: $ca_cert" 10
	[ -f "$crl_pem" ] || die "Missing: $crl_pem" 10
	[ -f "$index_txt" ] || die "Missing: $index_txt" 10
	#[ -f "$openssl_cnf" ] || die "Missing: $openssl_cnf" 10
	[ -f "$openvpn_metadata_file" ] || \
		die "Missing: openvpn_metadata_file: $openvpn_metadata_file" 10
}

#######################################

# Initialise
init


# Options
while [ -n "$1" ]
do
	case "$1" in
		help|-h|-help|--help)
					help_text ;;
		-1|-m1|--method-1)
					test_method=1 ;;
		-2|-m2|--method-2)
					test_method=2 ;;
		-v|--verbose)
					TLS_CRYPT_V2_VERIFY_VERBOSE=1 ;;
		-g|--custom-group)
					[ -z "$2" ] && \
						die "Missing custom group" 253

					TLS_CRYPT_V2_VERIFY_CG="$2"
					shift ;;
		-a|--allow-ss)
		# Allow client cert serial numbers of any length
					allow_only_random_serno=0 ;;
		*)
					die "Unknown option: $1" 253 ;;
	esac
	shift
done


# deps
deps


# Metadata Version
	metadata_version="$(fn_metadata_version)"
	case $metadata_version in
	metadata_version_A2)
		success_msg=" $metadata_version ==>" ;;
	*)
		insert_msg="TLS crypt v2 metadata version is not recognised:"
		failure_msg="$insert_msg $metadata_version"
		fail_and_exit "METADATA_VERSION" 7 ;;
	esac


# Metadata custom_group
	if [ -n "$TLS_CRYPT_V2_VERIFY_CG" ]
	then
		metadata_custom_group="$(fn_metadata_custom_group)"
		if [ "$metadata_custom_group" = "$TLS_CRYPT_V2_VERIFY_CG" ]
		then
			insert_msg="custom_group $metadata_custom_group OK ==>"
			success_msg="$success_msg $insert_msg"
		else
			insert_msg=" metadata custom_group is not correct:"
			[ -z "$metadata_custom_group" ] && \
				insert_msg=" metadata custom_group is missing"
			failure_msg="$insert_msg $metadata_custom_group"
			fail_and_exit "METADATA_CG" 8
		fi
	fi


# CA Fingerprint

	# Verify CA
	verify_ca || die "Bad CA $ca_cert" 11

	# Capture CA fingerprint
	# Format to one contiguous string (Same as encoded metadata)
	local_ca_fingerprint="$(fn_local_ca_fingerprint)"

	# local_ca_fingerprint is required
	[ -z "$local_ca_fingerprint" ] && \
		fail_and_exit "Missing: local CA fingerprint" 3

	# Collect CA fingerprint from tls-crypt-v2 metadata
	metadata_ca_fingerprint="$(fn_metadata_ca_fingerprint)"

	# metadata_ca_fingerprint is required
	[ -z "$metadata_ca_fingerprint" ] && \
		fail_and_exit "Missing: remote CA fingerprint" 3

# Check metadata CA fingerprint against local CA fingerprint
if [ "$local_ca_fingerprint" = "$metadata_ca_fingerprint" ]
then
	success_msg="$success_msg CA Fingerprint OK ==>"
else
	failure_msg="$failure_msg CA Fingerprint mismatch"
	fail_and_exit "FP_MISMATCH" 3
fi


# Client certificate serial number

	# Verify CRL
	verify_crl || die "Bad CRL: $crl_pem" 12

	# Capture CRL
	crl_text="$(fn_read_crl)"

	# Collect client certificate serial number from tls-crypt-v2 metadata
	# Drop the 'serial=' part
	metadata_client_cert_serno="$(fn_metadata_client_cert_serno)"

	# Client serial number requirements
	verify_metadata_client_serial_number

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
		#verify_openssl_serial_status
		serial_status_via_ca
	;;
	*)
		die "Unknown method for verify: $test_method" 9
	;;
esac


[ $absolute_fail -eq 0 ] || fail_and_exit "Nein" 9
[ $TLS_CRYPT_V2_VERIFY_VERBOSE ] && \
	"$printf_bin" "%s%s\n" "$tls_crypt_v2_verify_msg" "$success_msg"

exit 0
