"""Deploy KTPMatchHandler score-persistence spike v1.2 to ATL:27019.

Pickup of 2026-05-20 paused validation pass:
  - KTPAMXX  branch: feature/dodx-score-persistence-spike-v1.2 (commit 851295e4)
  - dodx_ktp_i386.so  expected md5: 41e50ede82c72f91e57c219a30b5af82  (KTPAMXX build dir)
  - KTPMatchHandler.amxx (KTP_TEST_MODE=1) expected md5: 4643f2ef5384e537cebd8b767265f2e1

Procedure:
  1. Stop  ~/dod-27019/dodserver5 stop
  2. Backup current binaries as .bak-pre-spike-20260521
  3. SCP both binaries into place
  4. Verify md5 matches local
  5. Start ~/dod-27019/dodserver5 start
  6. Tail console for event=DODX_STATS_NATIVES + 10/10 plugins
"""
import hashlib
import io
import os
import sys
import time
import paramiko

# Force UTF-8 on Windows stdout to handle Discord/console Unicode glyphs
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

HOST = '74.91.121.9'
USER = 'dodserver'
PASS = 'ktp'
PORT_DIR = 'dod-27019'
LGSM_BIN = 'dodserver5'
BACKUP_SUFFIX = '.bak-pre-spike-v1.3-20260521'  # second deploy window 2026-05-21

# Path candidates — script may run under Windows Python OR WSL Python.
# Use whichever set of paths actually resolves.
_CANDIDATES = [
    (r'N:\Nein_\KTP Git Projects\KTPAMXX\obj-linux\packages\dod\addons\ktpamx\modules\dodx_ktp_i386.so',
     r'N:\Nein_\KTP Git Projects\KTPMatchHandler\compiled\test\KTPMatchHandler.amxx'),
    ('/mnt/n/Nein_/KTP Git Projects/KTPAMXX/obj-linux/packages/dod/addons/ktpamx/modules/dodx_ktp_i386.so',
     '/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler/compiled/test/KTPMatchHandler.amxx'),
]
LOCAL_DODX = LOCAL_PLUGIN = None
for dodx, plugin in _CANDIDATES:
    if os.path.exists(dodx) and os.path.exists(plugin):
        LOCAL_DODX, LOCAL_PLUGIN = dodx, plugin
        break
if LOCAL_DODX is None:
    raise SystemExit(f'FATAL: neither path set resolved on this host. Tried:\n  {_CANDIDATES}')

REMOTE_DODX = f'/home/dodserver/{PORT_DIR}/serverfiles/dod/addons/ktpamx/modules/dodx_ktp_i386.so'
REMOTE_PLUGIN = f'/home/dodserver/{PORT_DIR}/serverfiles/dod/addons/ktpamx/plugins/KTPMatchHandler.amxx'

EXPECTED_DODX_MD5 = '941bd53f129938f1e21672657514d114'      # spike v1.3.3 — adds dodx_broadcast_scoreboard (safe C++ MESSAGE_BEGIN)
EXPECTED_PLUGIN_MD5 = '4ab4a02d3b361b117f95519f1c659c51'    # v1.3.3 — calls dodx_broadcast_scoreboard at RESTORE


def local_md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def run(ssh, cmd, timeout=60):
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode('utf-8', errors='replace').rstrip()
    err = stderr.read().decode('utf-8', errors='replace').rstrip()
    code = stdout.channel.recv_exit_status()
    return code, out, err


def section(label):
    print(f'\n=== {label} ===', flush=True)


def main():
    # ---- 0. Local artifact verification --------------------------------------
    section('Local artifact verification')
    d_md5 = local_md5(LOCAL_DODX)
    p_md5 = local_md5(LOCAL_PLUGIN)
    print(f'  dodx     md5={d_md5}  (expected {EXPECTED_DODX_MD5})')
    print(f'  plugin   md5={p_md5}  (expected {EXPECTED_PLUGIN_MD5})')
    if d_md5 != EXPECTED_DODX_MD5:
        sys.exit(f'FATAL: local dodx md5 mismatch — got {d_md5}, expected {EXPECTED_DODX_MD5}')
    if p_md5 != EXPECTED_PLUGIN_MD5:
        sys.exit(f'FATAL: local plugin md5 mismatch — got {p_md5}, expected {EXPECTED_PLUGIN_MD5}')

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f'\nConnecting to {USER}@{HOST}...')
    ssh.connect(HOST, username=USER, password=PASS, timeout=15)
    print('  connected.')

    # ---- 1. Pre-flight: capture current md5 + plugin version -----------------
    section('Pre-flight (before stop)')
    for label, remote in [('dodx', REMOTE_DODX), ('plugin', REMOTE_PLUGIN)]:
        code, out, err = run(ssh, f'md5sum {remote}')
        print(f'  current {label}: {out or err}')

    # ---- 2. Stop server ------------------------------------------------------
    section(f'Stop {PORT_DIR}/{LGSM_BIN}')
    code, out, err = run(ssh, f'cd ~/{PORT_DIR} && ./{LGSM_BIN} stop', timeout=120)
    print(out)
    if err:
        print(f'  stderr: {err}')

    # Confirm hlds_linux for this port is gone before SCP
    code, pgrep_out, _ = run(ssh, "pgrep -af 'hlds_linux.*-port 27019' || echo CLEAR")
    print(f'  pgrep post-stop: {pgrep_out}')
    if 'hlds_linux' in pgrep_out and 'CLEAR' not in pgrep_out:
        ssh.close()
        sys.exit('FATAL: hlds_linux still running on port 27019 after stop — aborting')

    # ---- 3. Backup current binaries ------------------------------------------
    section('Backup current binaries (.bak-pre-spike-20260521)')
    for label, remote in [('dodx', REMOTE_DODX), ('plugin', REMOTE_PLUGIN)]:
        bak = f'{remote}{BACKUP_SUFFIX}'
        # Use -n to avoid clobbering an existing backup from prior pickup
        code, out, err = run(ssh, f'cp -n {remote} {bak} && md5sum {bak}')
        print(f'  {label}: {out or err}')

    # ---- 4. SFTP upload ------------------------------------------------------
    section('SFTP upload')
    sftp = ssh.open_sftp()

    for label, local, remote in [
        ('dodx', LOCAL_DODX, REMOTE_DODX),
        ('plugin', LOCAL_PLUGIN, REMOTE_PLUGIN),
    ]:
        t0 = time.time()
        sftp.put(local, remote)
        dt = time.time() - t0
        sz = os.path.getsize(local)
        print(f'  uploaded {label}: {sz} bytes in {dt:.2f}s ({sz/1024/max(dt,0.001):.0f} KB/s)')

    sftp.close()

    # ---- 5. Remote md5 verify ------------------------------------------------
    section('Remote md5 verify')
    for label, remote, expected in [
        ('dodx', REMOTE_DODX, EXPECTED_DODX_MD5),
        ('plugin', REMOTE_PLUGIN, EXPECTED_PLUGIN_MD5),
    ]:
        code, out, err = run(ssh, f'md5sum {remote}')
        got = out.split()[0] if out else '<NONE>'
        ok = got == expected
        print(f'  {label}: {got}  expected={expected}  {"OK" if ok else "MISMATCH"}')
        if not ok:
            ssh.close()
            sys.exit(f'FATAL: post-upload {label} md5 mismatch')

    # ---- 6. Start server -----------------------------------------------------
    section(f'Start {PORT_DIR}/{LGSM_BIN}')
    code, out, err = run(ssh, f'cd ~/{PORT_DIR} && ./{LGSM_BIN} start', timeout=120)
    print(out)
    if err:
        print(f'  stderr: {err}')

    # Belt-and-suspenders: recreate the LinuxGSM monitoring lockfile if missing
    # (mirrors the fix in ktp-scheduled-restart.sh — fleet-wide patch from 4/23).
    run(ssh, f'cd ~/{PORT_DIR}/lgsm/lock && [ ! -f {LGSM_BIN}-monitoring.lock ] && date +%s > {LGSM_BIN}-monitoring.lock || true')

    # ---- 7. Tail console for plugin-init confirmation ------------------------
    section('Tail console for DODX_STATS_NATIVES + 10/10 plugins')
    # Wait up to ~25s for the server to come up + emit plugin_init lines
    print('  waiting 15s for server to initialize...')
    time.sleep(15)

    # LinuxGSM v25.2.0 names the log dodserver5-console.log (not console.log).
    code, out, err = run(ssh, f'tail -200 ~/{PORT_DIR}/log/console/{LGSM_BIN}-console.log 2>/dev/null | grep -E "DODX_STATS_NATIVES|KTP-TEST-MODE|plugins, .* running|FATAL|SEGFAULT|crash|score/deaths offset" | tail -40')
    if out:
        print(out)
    else:
        print('  (no matching lines yet — server may still be initializing)')

    ssh.close()

    section('DEPLOY COMPLETE')
    print('Next step: drive to LIVE via the 3 test rcons (run separately).')


if __name__ == '__main__':
    main()
