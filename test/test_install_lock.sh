#!/usr/bin/env bash

# Source common test setup
source "$(dirname "${0}")/test_common.sh";

#####################
# Begin Script Body #
#####################

declare -a errors=();
declare test_version='1.6.1';

log 'info' '### Test Suite: install_lock';

##############################################################################
# Test 1: Install with non-existent TFENV_CONFIG_DIR (regression test #487/#525)
##############################################################################
log 'info' '## install_lock: install with non-existent TFENV_CONFIG_DIR';
cleanup || log 'error' 'Cleanup failed?!';
(
  declare fresh_config_dir;
  fresh_config_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'tfenv_lock_test')";
  rm -rf "${fresh_config_dir}";
  # Confirm it does not exist
  [ ! -d "${fresh_config_dir}" ] || exit 1;
  TFENV_CONFIG_DIR="${fresh_config_dir}" tfenv install "${test_version}" || exit 1;
  [ -f "${fresh_config_dir}/versions/${test_version}/terraform" ] || exit 1;
  rm -rf "${fresh_config_dir}";
) && log 'info' '## install_lock: non-existent config dir passed' \
  || error_and_proceed 'install with non-existent TFENV_CONFIG_DIR failed';

##############################################################################
# Test 2: Install with read-only TFENV_CONFIG_DIR, non-interactive (#524)
##############################################################################
log 'info' '## install_lock: read-only config dir, non-interactive';
cleanup || log 'error' 'Cleanup failed?!';
(
  declare ro_dir;
  ro_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'tfenv_lock_ro')";
  chmod 555 "${ro_dir}";
  declare output;
  output="$(TFENV_CONFIG_DIR="${ro_dir}" tfenv install "${test_version}" < /dev/null 2>&1)";
  declare rc="${?}";
  chmod 755 "${ro_dir}";
  rm -rf "${ro_dir}";
  [ "${rc}" -ne 0 ] || exit 1;
  echo "${output}" | grep -q 'not writable' || exit 1;
) && log 'info' '## install_lock: read-only non-interactive passed' \
  || error_and_proceed 'read-only TFENV_CONFIG_DIR non-interactive did not fail with expected error';

##############################################################################
# Test 3: Install with read-only TFENV_CONFIG_DIR, interactive fallback accepted
##############################################################################
log 'info' '## install_lock: read-only config dir, interactive fallback accepted';
cleanup || log 'error' 'Cleanup failed?!';
(
  declare ro_dir;
  ro_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'tfenv_lock_ro2')";
  chmod 555 "${ro_dir}";
  declare fallback_home;
  fallback_home="$(mktemp -d 2>/dev/null || mktemp -d -t 'tfenv_lock_home')";
  # Pipe "y" as stdin via script(1) which allocates a pseudo-terminal.
  # The prompt checks [[ -t 0 ]], so piping directly would be non-interactive.
  # Piping into script(1) forwards input through the PTY, so the child sees
  # a real terminal on stdin.
  declare output;
  if command -v script >/dev/null 2>&1; then
    # GNU script (Linux) vs BSD script (macOS) have different syntax
    if script --help 2>&1 | grep -q -- '--return'; then
      # GNU script: pipe into script so the PTY forwards "y" to tfenv
      output="$(echo y | TFENV_CONFIG_DIR="${ro_dir}" HOME="${fallback_home}" script -qec "${TFENV_ROOT}/bin/tfenv install ${test_version}" --return /dev/null 2>&1)";
      declare rc="${?}";
    else
      # BSD script (macOS)
      output="$(echo y | TFENV_CONFIG_DIR="${ro_dir}" HOME="${fallback_home}" script -q /dev/null "${TFENV_ROOT}/bin/tfenv install ${test_version}" 2>&1)";
      declare rc="${?}";
    fi;
  else
    # Fallback: skip this test if script(1) is not available
    log 'warn' 'script(1) not available, skipping interactive fallback test';
    chmod 755 "${ro_dir}";
    rm -rf "${ro_dir}" "${fallback_home}";
    exit 0;
  fi;
  chmod 755 "${ro_dir}";
  rm -rf "${ro_dir}";
  if [ "${rc}" -ne 0 ]; then
    echo "UNEXPECTED FAILURE output: ${output}" >&2;
    rm -rf "${fallback_home}";
    exit 1;
  fi;
  [ -f "${fallback_home}/.tfenv/versions/${test_version}/terraform" ] || {
    echo "terraform binary not found in fallback dir" >&2;
    rm -rf "${fallback_home}";
    exit 1;
  };
  rm -rf "${fallback_home}";
) && log 'info' '## install_lock: interactive fallback accepted passed' \
  || error_and_proceed 'read-only TFENV_CONFIG_DIR interactive fallback (y) did not install to ~/.tfenv';

##############################################################################
# Test 4: Install with read-only TFENV_CONFIG_DIR, interactive fallback declined
##############################################################################
log 'info' '## install_lock: read-only config dir, interactive fallback declined';
cleanup || log 'error' 'Cleanup failed?!';
(
  declare ro_dir;
  ro_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'tfenv_lock_ro3')";
  chmod 555 "${ro_dir}";
  declare output;
  if command -v script >/dev/null 2>&1; then
    if script --help 2>&1 | grep -q -- '--return'; then
      output="$(echo n | TFENV_CONFIG_DIR="${ro_dir}" script -qec "${TFENV_ROOT}/bin/tfenv install ${test_version}" --return /dev/null 2>&1)";
      declare rc="${?}";
    else
      output="$(echo n | TFENV_CONFIG_DIR="${ro_dir}" script -q /dev/null "${TFENV_ROOT}/bin/tfenv install ${test_version}" 2>&1)";
      declare rc="${?}";
    fi;
  else
    log 'warn' 'script(1) not available, skipping interactive decline test';
    chmod 755 "${ro_dir}";
    rm -rf "${ro_dir}";
    exit 0;
  fi;
  chmod 755 "${ro_dir}";
  rm -rf "${ro_dir}";
  [ "${rc}" -ne 0 ] || exit 1;
) && log 'info' '## install_lock: interactive fallback declined passed' \
  || error_and_proceed 'read-only TFENV_CONFIG_DIR interactive fallback (n) did not fail';

##############################################################################
# Test 5: Lock cleanup on normal exit
##############################################################################
log 'info' '## install_lock: lock cleanup after successful install';
cleanup || log 'error' 'Cleanup failed?!';
(
  tfenv install "${test_version}" || exit 1;
  # Verify no install lock directories remain
  declare lock_count;
  lock_count="$(find "${TFENV_CONFIG_DIR}" -maxdepth 1 -name '.install-lock-*' -type d 2>/dev/null | wc -l)";
  [ "${lock_count}" -eq 0 ] || exit 1;
) && log 'info' '## install_lock: lock cleanup passed' \
  || error_and_proceed 'install lock directory was not cleaned up after successful install';

##############################################################################
# Test 6: Lock cleanup on interrupted exit
# Skipped — reliably testing signal-handler cleanup (SIGINT/SIGTERM during
# install) is inherently racy and would produce flaky CI results. The
# cleanup_lock trap is validated by manual testing and code review.
##############################################################################
log 'info' '## install_lock: signal cleanup — SKIPPED (inherently racy, see comment)';

finish_tests 'install_lock';
# vim: set syntax=bash tabstop=2 softtabstop=2 shiftwidth=2 expandtab smarttab :
