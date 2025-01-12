# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

EAPI=7
CROS_WORKON_COMMIT="ed3cbd39d08fafc9793396934088ef152c74ccc3"
CROS_WORKON_TREE=("52a8a8b6d3bbca5e90d4761aa308a5541d52b1bb" "0be9b01657e3488badf97e2e2160b2c16db87cef" "8d228c8e702aebee142bcbf0763a15786eb5b3bb" "e7dba8c91c1f3257c34d4a7ffff0ea2537aeb6bb")
CROS_WORKON_PROJECT="chromiumos/platform2"
CROS_WORKON_LOCALNAME="platform2"
CROS_WORKON_OUTOFTREE_BUILD=1
CROS_WORKON_INCREMENTAL_BUILD=1
# TODO(crbug.com/809389): Avoid #include-ing platform2 headers directly.
CROS_WORKON_SUBTREE="common-mk init metrics .gn"

PLATFORM_NATIVE_TEST="yes"
PLATFORM_SUBDIR="init"

inherit tmpfiles cros-workon platform user

DESCRIPTION="Upstart init scripts for Chromium OS"
HOMEPAGE="https://chromium.googlesource.com/chromiumos/platform2/+/master/init/"
SRC_URI=""

LICENSE="BSD-Google"
SLOT="0/0"
KEYWORDS="*"
IUSE="
	arcpp arcvm cros_embedded +debugd +encrypted_stateful +encrypted_reboot_vault
	frecon -lvm_stateful_partition kernel-3_8 kernel-3_10 kernel-3_14
	kernel-3_18 +midi -s3halt +syslog systemd +udev vivid vtconsole
  fydeos_factory_install fixcgroup fixcgroup-memory"

# secure-erase-file, vboot_reference, and rootdev are needed for clobber-state.
COMMON_DEPEND="
	>=chromeos-base/metrics-0.0.1-r3152:=
	chromeos-base/secure-erase-file:=
	chromeos-base/vboot_reference:=
	sys-apps/rootdev:=
"

DEPEND="${COMMON_DEPEND}
	test? (
		sys-process/psmisc
		dev-util/shunit2
		sys-apps/diffutils
	)
"

RDEPEND="${COMMON_DEPEND}
	app-arch/tar
	app-misc/jq
	chromeos-base/bootstat
	!chromeos-base/chromeos-disableecho
	chromeos-base/chromeos-common-script
	chromeos-base/tty
	sys-apps/upstart
	sys-process/lsof
	virtual/chromeos-bootcomplete
	!cros_embedded? (
		chromeos-base/common-assets
		chromeos-base/chromeos-storage-info
		chromeos-base/swap-init
		sys-fs/e2fsprogs
	)
	frecon? (
		sys-apps/frecon
	)
"

platform_pkg_test() {
	local shell_tests=(
		killers_unittest
		tests/chromeos-disk-metrics-test.sh
		tests/send-kernel-errors-test.sh
	)

	local test_bin
	for test_bin in "${shell_tests[@]}"; do
		platform_test "run" "./${test_bin}"
	done

	local cpp_tests=(
		clobber_state_test
		file_attrs_cleaner_test
		periodic_scheduler_test
		usermode-helper_test
	)

	for test_bin in "${cpp_tests[@]}"; do
		platform_test "run" "${OUT}/${test_bin}"
	done
}

src_install_upstart() {
	insinto /etc/init

	if use cros_embedded; then
		doins upstart/startup.conf
		doins upstart/embedded-init/boot-services.conf

		doins upstart/report-boot-complete.conf
		doins upstart/failsafe-delay.conf upstart/failsafe.conf
		doins upstart/pre-shutdown.conf upstart/pre-startup.conf
		doins upstart/pstore.conf upstart/reboot.conf
		doins upstart/system-services.conf
		doins upstart/uinput.conf
		doins upstart/sysrq-init.conf

		if use syslog; then
			doins upstart/log-rotate.conf upstart/syslog.conf upstart/journald.conf
			dotmpfiles tmpfiles.d/syslog.conf
		fi
		if use !systemd; then
			doins upstart/cgroups.conf
			doins upstart/dbus.conf
			dotmpfiles tmpfiles.d/dbus.conf
			if use udev; then
				doins upstart/udev.conf upstart/udev-trigger.conf
				doins upstart/udev-trigger-early.conf
			fi
		fi
		if use frecon; then
			doins upstart/boot-splash.conf
		fi
	else
		doins upstart/*.conf
		dotmpfiles tmpfiles.d/*.conf

		if ! use arcpp && use arcvm; then
			sed -i '/^env IS_ARCVM=/s:=0:=1:' \
				"${D}/etc/init/rt-limits.conf" || \
				die "Failed to replace is_arcvm in rt-limits.conf"
		fi

		dosbin chromeos-disk-metrics
		dosbin chromeos-send-kernel-errors
		dosbin display_low_battery_alert
	fi

	if ! use debugd; then
		sed -i '/^env PSTORE_GROUP=/s:=.*:=root:' \
			"${D}/etc/init/pstore.conf" || \
			die "Failed to replace PSTORE_GROUP in pstore.conf"
	fi

	if use midi; then
		if use kernel-3_8 || use kernel-3_10 || use kernel-3_14 || use kernel-3_18; then
			doins upstart/workaround-init/midi-workaround.conf
		fi
	fi

	if use s3halt; then
		newins upstart/halt/s3halt.conf halt.conf
	else
		doins upstart/halt/halt.conf
	fi

	if use vivid; then
		doins upstart/vivid/vivid.conf
	fi

	use vtconsole && doins upstart/vtconsole/*.conf
}

src_install() {
	# Install helper to run periodic tasks.
	dobin "${OUT}"/periodic_scheduler

	if use syslog; then
		# Install log cleaning script and run it daily.
		dosbin chromeos-cleanup-logs

		insinto /etc
		doins rsyslog.chromeos
	fi

	insinto /usr/share/cros
	doins *_utils.sh

	exeinto /usr/share/cros/init
	doexe is_feature_enabled.sh

	into /	# We want /sbin, not /usr/sbin, etc.

	# Install various utility files.
	dosbin killers

	# Install various helper programs.
	dosbin "${OUT}"/cros_sysrq_init
	dosbin "${OUT}"/static_node_tool
	dosbin "${OUT}"/net_poll_tool
	dosbin "${OUT}"/file_attrs_cleaner_tool
	dosbin "${OUT}"/usermode-helper

	# Install startup/shutdown scripts.
	dosbin chromeos_startup chromeos_shutdown

	# Disable encrypted reboot vault if it is not used.
	if ! use encrypted_reboot_vault; then
		sed -i '/USE_ENCRYPTED_REBOOT_VAULT=/s:=1:=0:' \
			"${D}/sbin/chromeos_startup" ||
			die "Failed to replace USE_ENCRYPTED_REBOOT_VAULT in chromeos_startup"
	fi

	# Enable lvm stateful partition.
	if use lvm_stateful_partition; then
		sed -i '/USE_LVM_STATEFUL_PARTITION=/s:=0:=1:' \
			"${D}/sbin/chromeos_startup" ||
			die "Failed to replace USE_LVM_STATEFUL_PARTITION in chromeos_startup"
	fi

	dosbin "${OUT}"/clobber-state

	dosbin clobber-log
	dosbin chromeos-boot-alert

	# Install Upstart scripts.
	src_install_upstart

	insinto /usr/share/cros
	doins $(usex encrypted_stateful encrypted_stateful \
		unencrypted_stateful)/startup_utils.sh

	# Install LVM conf files.
	if use lvm_stateful_partition; then
		insinto /etc/lvm
		doins lvm.conf
	fi
}

pkg_preinst() {
	# Add the syslog user
	enewuser syslog
	enewgroup syslog

	# Create debugfs-access user and group, which is needed by the
	# chromeos_startup script to mount /sys/kernel/debug.  This is needed
	# by bootstat and ureadahead.
	enewuser "debugfs-access"
	enewgroup "debugfs-access"
}

src_prepare() {
  if use fydeos_factory_install; then
    eapply ${FILESDIR}/insert_factory_install_script.patch
    eapply ${FILESDIR}/set_default_language_to_zh.patch
    if [ -n "${FYDEOS_FACTORY_INSTALL}" ]; then
      echo $FYDEOS_FACTORY_INSTALL > $FYDEOS_INSTALL_FILE
    fi
  fi
  if use fixcgroup; then
    eapply -p2 ${FILESDIR}/cgroups_cpuset.patch
  fi
  if use fixcgroup-memory; then
    eapply -p2 ${FILESDIR}/fix_cgroup_memory.patch
  fi
  eapply -p2 ${FILESDIR}/change_splash_background_color_black.patch
  eapply -p2 ${FILESDIR}/block_frecon_vtconsole.patch
  default
}
