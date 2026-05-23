"""One-shot deploy: SCP KTPMatchHandler.amxx 0.10.133 to ATL5 as .new + status check.

Used 2026-05-22 for the spray-baseline recording setup on ATL5 (port 27019).
After SCP, the .new file sits until the next ATL5 restart (manual or 3am cron).
"""
import paramiko
import sys
import os
from pathlib import Path

HOST = "74.91.121.9"      # ATL baremetal
USER = "dodserver"
PASS = "ktp"
LOCAL = r"N:\Nein_\KTP Git Projects\KTPMatchHandler\compiled\KTPMatchHandler.amxx"
REMOTE_DIR = "/home/dodserver/dod-27019/serverfiles/dod/addons/ktpamx/plugins"
REMOTE_NEW = f"{REMOTE_DIR}/KTPMatchHandler.amxx.new"
REMOTE_ACTIVE = f"{REMOTE_DIR}/KTPMatchHandler.amxx"


def main():
    if not os.path.exists(LOCAL):
        print(f"Local plugin not found: {LOCAL}", file=sys.stderr)
        return 1

    local_size = os.path.getsize(LOCAL)
    print(f"Local plugin: {LOCAL} ({local_size} bytes)")

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username=USER, password=PASS, timeout=30)

    # Quick status pre-deploy
    print("\n=== Pre-deploy state ===")
    for cmd in [
        f"ls -la {REMOTE_ACTIVE} 2>&1 | head -1",
        f"ls -la {REMOTE_NEW} 2>&1 | head -1",
        # Active plugin version (md5)
        f"md5sum {REMOTE_ACTIVE} 2>&1 | head -1",
        # ATL5 player count
        "~/dod-27019/dodserver5 details 2>&1 | grep -E 'Players|Online' | head -2",
    ]:
        stdin, stdout, stderr = ssh.exec_command(cmd, timeout=15)
        out = stdout.read().decode().strip()
        err = stderr.read().decode().strip()
        if out:
            print(f"  $ {cmd}\n    {out}")
        if err and "No such file" not in err:
            print(f"    [stderr] {err}")

    # SCP via SFTP
    print(f"\n=== SCP local -> {REMOTE_NEW} ===")
    sftp = ssh.open_sftp()
    sftp.put(LOCAL, REMOTE_NEW)
    sftp.close()

    # Verify SCP
    stdin, stdout, stderr = ssh.exec_command(f"ls -la {REMOTE_NEW} && md5sum {REMOTE_NEW}", timeout=15)
    print(stdout.read().decode().strip())
    err = stderr.read().decode().strip()
    if err:
        print(f"[stderr] {err}", file=sys.stderr)

    ssh.close()
    print("\n=== SCP complete ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
