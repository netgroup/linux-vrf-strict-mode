#!/bin/bash
# SPDX-License-Identifier: GPL-2.0

# This test is designed for testing the new vrf strict_mode functionality.

ret=0

PAUSE_ON_FAIL=${PAUSE_ON_FAIL:=no}
NETNS="ip netns exec testns"

log_test()
{
	local rc=$1
	local expected=$2
	local msg="$3"

	if [ ${rc} -eq ${expected} ]; then
		nsuccess=$((nsuccess+1))
		printf "\n    TEST: %-60s  [ OK ]\n" "${msg}"
	else
		ret=1
		nfail=$((nfail+1))
		printf "\n    TEST: %-60s  [FAIL]\n" "${msg}"
		if [ "${PAUSE_ON_FAIL}" = "yes" ]; then
			echo
			echo "hit enter to continue, 'q' to quit"
			read a
			[ "$a" = "q" ] && exit 1
		fi
	fi
}

print_log_test_results()
{
	if [ "$TESTS" != "none" ]; then
		printf "\nTests passed: %3d\n" ${nsuccess}
		printf "Tests failed: %3d\n"   ${nfail}
	fi
}

log_section()
{
	echo
	echo "################################################################################"
	echo "TEST SECTION: $*"
	echo "################################################################################"
}

set_netns()
{
	local nsname=$1
	local nsexec=''

	if [ "${nsname}" != "rootns" ]; then
		nsexec="ip netns exec ${nsname}"
	fi

	echo "${nsexec}"
	return 0
}

vrf_count()
{
	local nsname=$1
	local netns="$(set_netns ${nsname})"

	${netns} ip -d link show | grep 'vrf table' | wc -l
}

count_vrf_by_table_id()
{
	local nsname=$1
	local tableid=$2
	local netns="$(set_netns ${nsname})"

	${netns} ip -d link show | grep "vrf table ${tableid}" | wc -l
}

add_vrf()
{
	local nsname=$1
	local vrfname=$2
	local vrftable=$3
	local netns="$(set_netns ${nsname})"

	${netns} ip link add ${vrfname} type vrf table ${vrftable} &>/dev/null
}

add_vrf_and_check()
{
	local nsname=$1
	local vrfname=$2
	local vrftable=$3
	local netns="$(set_netns ${nsname})"
	local cnt
	local rc

	add_vrf ${nsname} ${vrfname} ${vrftable}; rc=$?

	cnt=$(count_vrf_by_table_id ${nsname} ${vrftable})

	log_test ${rc} 0 "${nsname}: add vrf ${vrfname}, ${cnt} vrfs for table ${vrftable}"
}

add_vrf_and_check_fail()
{
	local nsname=$1
	local vrfname=$2
	local vrftable=$3
	local netns="$(set_netns ${nsname})"
	local cnt
	local rc

	add_vrf ${nsname} ${vrfname} ${vrftable}; rc=$?

	cnt=$(count_vrf_by_table_id ${nsname} ${vrftable})

	log_test ${rc} 2 "${nsname}: CANNOT add vrf ${vrfname}, ${cnt} vrfs for table ${vrftable}"
}

del_vrf_and_check()
{
	local nsname=$1
	local vrfname=$2
	local netns="$(set_netns ${nsname})"

	${netns} ip link del ${vrfname}
	log_test $? 0 "${nsname}: remove vrf ${vrfname}"
}

config_vrf_and_check()
{
	local nsname=$1
	local addr=$2
	local vrfname=$3
	local netns="$(set_netns ${nsname})"

	${netns} ip link set dev ${vrfname} up && \
		${netns} ip addr add ${addr} dev ${vrfname}
	log_test $? 0 "${nsname}: vrf ${vrfname} up, addr ${addr}"
}

read_strict_mode()
{
	local nsname=$1
	local rval
	local rc
	local netns="$(set_netns ${nsname})"

	rc=0
	rval="$(${netns} bash -c "cat /proc/sys/net/vrf/strict_mode" | \
		grep -E "^[0-1]$")" &> /dev/null
	if [ $? -ne 0 ]; then
		rval=255
		rc=1
	fi

	# rval can only be 0 or 1
	echo ${rval}
	return ${rc}
}

read_strict_mode_compare_and_check()
{
	local nsname=$1
	local expected=$2
	local res

	res="$(read_strict_mode ${nsname})"
	log_test ${res} ${expected} "${nsname}: strict_mode=${res}"
}

set_strict_mode()
{
	local nsname=$1
	local val=$2
	local netns="$(set_netns ${nsname})"

	${netns} bash -c "echo ${val} >/proc/sys/net/vrf/strict_mode" &>/dev/null
}

enable_strict_mode()
{
	local nsname=$1

	set_strict_mode ${nsname} 1
}

disable_strict_mode()
{
	local nsname=$1

	set_strict_mode ${nsname} 0
}

disable_strict_mode_and_check()
{
	local nsname=$1

	disable_strict_mode ${nsname}
	log_test $? 0 "${nsname}: disable strict_mode (=0)"
}

enable_strict_mode_and_check()
{
	local nsname=$1

	enable_strict_mode ${nsname}
	log_test $? 0 "${nsname}: enable strict_mode (=1)"
}

enable_strict_mode_and_check_fail()
{
	local nsname=$1

	enable_strict_mode ${nsname}
	log_test $? 1 "${nsname}: CANNOT enable strict_mode"
}

strict_mode_check_default()
{
	local nsname=$1
	local strictmode
	local vrfcnt

	vrfcnt=$(vrf_count ${nsname})
	strictmode=$(read_strict_mode ${nsname})
	log_test ${strictmode} 0 "${nsname}: strict_mode=0 by default, ${vrfcnt} vrfs"
}

setup()
{
	modprobe vrf

	ip netns add testns
	ip netns exec testns ip link set lo up
}

cleanup()
{
	ip netns del testns 2>/dev/null

	ip link del vrf100 2>/dev/null
	ip link del vrf101 2>/dev/null
	ip link del vrf102 2>/dev/null

	echo 0 >/proc/sys/net/vrf/strict_mode 2>/dev/null
}

vrf_strict_mode_tests_rootns()
{
	vrf_strict_mode_check_support rootns

	strict_mode_check_default rootns

	add_vrf_and_check rootns vrf100 100
	config_vrf_and_check rootns 172.16.100.1/24 vrf100

	enable_strict_mode_and_check rootns

	add_vrf_and_check_fail rootns vrf101 100

	disable_strict_mode_and_check rootns

	add_vrf_and_check rootns vrf101 100
	config_vrf_and_check rootns 172.16.101.1/24 vrf101

	enable_strict_mode_and_check_fail rootns

	del_vrf_and_check rootns vrf101

	enable_strict_mode_and_check rootns

	add_vrf_and_check rootns vrf102 102
	config_vrf_and_check rootns 172.16.102.1/24 vrf102

	# the strict_modle is enabled in the rootns
}

vrf_strict_mode_tests_testns()
{
	vrf_strict_mode_check_support testns

	strict_mode_check_default testns

	enable_strict_mode_and_check testns

	add_vrf_and_check testns vrf100 100
	config_vrf_and_check testns 10.0.100.1/24 vrf100

	add_vrf_and_check_fail testns vrf101 100

	add_vrf_and_check_fail testns vrf102 100

	add_vrf_and_check testns vrf200 200

	disable_strict_mode_and_check testns

	add_vrf_and_check testns vrf101 100

	add_vrf_and_check testns vrf102 100

	#the strict_mode is disabled in the testns
}

vrf_strict_mode_tests_mix()
{
	read_strict_mode_compare_and_check rootns 1

	read_strict_mode_compare_and_check testns 0

	del_vrf_and_check testns vrf101

	del_vrf_and_check testns vrf102

	disable_strict_mode_and_check rootns

	enable_strict_mode_and_check testns

	enable_strict_mode_and_check rootns
	enable_strict_mode_and_check rootns

	disable_strict_mode_and_check testns
	disable_strict_mode_and_check testns

	read_strict_mode_compare_and_check rootns 1

	read_strict_mode_compare_and_check testns 0
}

vrf_strict_mode_tests()
{
	log_section "VRF strict_mode test on root network namespace"
	vrf_strict_mode_tests_rootns

	log_section "VRF strict_mode test on testns network namespace"
	vrf_strict_mode_tests_testns

	log_section "VRF strict_mode test mixing root and testns network namespaces"
	vrf_strict_mode_tests_mix
}

vrf_strict_mode_check_support()
{
	local nsname=$1
	local output
	local netns="$(set_netns ${nsname})"
	local rc

	output="$(lsmod | grep '^vrf' | awk '{print $1}')"
	if [ -z "${output}" ]; then
		modinfo vrf || return $?
	fi

	${netns} bash -c 'cat /proc/sys/net/vrf/strict_mode' &>/dev/null
	rc=$?
	log_test ${rc} 0 "${nsname}: net.vrf.strict_mode is available"

	return ${rc}
}

if [ "$(id -u)" -ne 0 ];then
	echo "SKIP: Need root privileges"
	exit 0
fi

if [ ! -x "$(command -v ip)" ]; then
	echo "SKIP: Could not run test without ip tool"
	exit 0
fi

cleanup &> /dev/null

setup
vrf_strict_mode_tests
cleanup

print_log_test_results

exit $ret
