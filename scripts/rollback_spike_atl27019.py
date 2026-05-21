"""Rollback ATL:27019 from spike v1.2 back to pre-spike production binaries.

Restores the .bak-pre-spike-20260521 backups taken during the 2026-05-21 deploy
(md5 reference: dodx cb670f75088409389ce1baed75b470cb, plugin 3f1566559e0f2d3420d9c3f744925aca).

Procedure mirrors deploy script:
  1. Stop dodserver5
  2. Restore .bak-pre-spike-20260521 → live filename
  3. Verify md5 matches the pre-spike fingerprint
  4. Start dodserver5
  5. Verify plugin init shows production version (0.10.121, not test-mode)
"""
import io
import os
import sys
import time
import paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

HOST = '74.91.121.9'
USER = 'dodserver'
PASS = 'ktp'
PORT_DIR = 'dod-27019'
LGSM_BIN = 'dodserver5'
BACKUP_SUFFIX = '.bak-pre-spike-20260521'

REMOTE_DODX = f'/home/dodserver/{PORT_DIR}/serverfiles/dod/addons/ktpamx/modules/dodx_ktp_i386.so'
REMOTE_PLUGIN = f'/home/dodserver/{PORT_DIR}/serverfiles/dod/addons/ktpamx/plugins/KTPMatchHandler.amxx'

EXPECTED_DODX_MD5 = 'cb670f75088409389ce1baed75b470cb'
EXPECTED_PLUGIN_MD5 = '3f1566559e0f2d3420d9c3f744925aca'

LOG = f'~/{PORT_DIR}/log/console/{LGSM_BIN}-console.log'


def run(ssh, cmd, timeout=60):
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    return (
        stdout.channel.recv_exit_status(),
        stdout.read().decode('utf-8', errors='replace').rstrip(),
        stderr.read().decode('utf-8', errors='replace').rstrip(),
    )


def section(label):
    print(f'\n=== {label} ===', flush=True)


def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f'Connecting to {USER}@{HOST}...')
    ssh.connect(HOST, username=USER, password=PASS, timeout=15)

    # 0. Confirm backups exist + match expected fingerprints
    section('Pre-flight: verify backup fingerprints')
    for label, remote, expected in [
        ('dodx', REMOTE_DODX, EXPECTED_DODX_MD5),
        ('plugin', REMOTE_PLUGIN, EXPECTED_PLUGIN_MD5),
    ]:
        bak = f'{remote}{BACKUP_SUFFIX}'
        code, out, _ = run(ssh, f'md5sum {bak}')
        got = out.split()[0] if out else '<NONE>'
        ok = got == expected
        print(f'  {label} backup: {got}  expected={expected}  {"OK" if ok else "MISMATCH — ABORTING"}')
        if not ok:
            ssh.close()
            sys.exit(f'FATAL: backup {label} md5 mismatch — refusing rollback')

    # 1. Stop server
    section(f'Stop {PORT_DIR}/{LGSM_BIN}')
    code, out, err = run(ssh, f'cd ~/{PORT_DIR} && ./{LGSM_BIN} stop', timeout=120)
    print(out)
    code, pg, _ = run(ssh, "pgrep -af 'hlds_linux.*-port 27019' || echo CLEAR")
    print(f'  pgrep post-stop: {pg}')
    if 'hlds_linux' in pg and 'CLEAR' not in pg:
        ssh.close()
        sys.exit('FATAL: hlds_linux still running on port 27019 after stop')

    # 2. Restore backups (cp -f to overwrite the spike binaries)
    section('Restore .bak-pre-spike-20260521')
    for label, remote in [('dodx', REMOTE_DODX), ('plugin', REMOTE_PLUGIN)]:
        bak = f'{remote}{BACKUP_SUFFIX}'
        code, out, err = run(ssh, f'cp -f {bak} {remote}')
        if code != 0:
            ssh.close()
            sys.exit(f'FATAL: restore {label} failed: {err}')
        print(f'  restored {label}')

    # 3. Verify md5
    section('Verify restored md5')
    for label, remote, expected in [
        ('dodx', REMOTE_DODX, EXPECTED_DODX_MD5),
        ('plugin', REMOTE_PLUGIN, EXPECTED_PLUGIN_MD5),
    ]:
        code, out, _ = run(ssh, f'md5sum {remote}')
        got = out.split()[0] if out else '<NONE>'
        ok = got == expected
        print(f'  {label}: {got}  {"OK" if ok else "MISMATCH"}')
        if not ok:
            ssh.close()
            sys.exit('FATAL: post-restore md5 mismatch — DO NOT START until investigated')

    # 4. Start server
    section(f'Start {PORT_DIR}/{LGSM_BIN}')
    code, out, err = run(ssh, f'cd ~/{PORT_DIR} && ./{LGSM_BIN} start', timeout=120)
    print(out)
    # Belt-and-suspenders monitor lockfile
    run(ssh, f'cd ~/{PORT_DIR}/lgsm/lock && [ ! -f {LGSM_BIN}-monitoring.lock ] && date +%s > {LGSM_BIN}-monitoring.lock || true')

    # 5. Wait + verify production version
    section('Verify production plugin version + DODX_STATS_NATIVES NOT loaded')
    print('  waiting 15s for server to initialize...')
    time.sleep(15)

    code, out, _ = run(ssh, f'grep -E "PLUGIN_ENABLED.*KTP Match Handler|KTP-TEST-MODE|DODX_STATS_NATIVES" {LOG} | tail -10')
    print(out if out else '(no matching lines)')

    # Expected on rollback success:
    #   - PLUGIN_ENABLED name='KTP Match Handler' version=0.10.121 (production)
    #   - NO [KTP-TEST-MODE] line
    #   - NO event=DODX_STATS_NATIVES line (those natives only exist in spike build)
    if '0.10.121' in out and '[KTP-TEST-MODE]' not in out and 'DODX_STATS_NATIVES' not in out:
        print('\n>>> ROLLBACK SUCCESS — production 0.10.121 active, spike removed')
    else:
        print('\n>>> WARNING: unexpected init pattern. Inspect log manually.')

    ssh.close()


if __name__ == '__main__':
    main()
