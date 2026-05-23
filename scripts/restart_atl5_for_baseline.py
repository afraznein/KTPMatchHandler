"""Restart ATL5 to activate the staged KTPMatchHandler.amxx.new plugin.

Checks player count first. If 0, proceeds with restart. If >0, aborts.
Used 2026-05-22 for the spray-baseline recording setup on ATL5.
"""
import paramiko
import sys
import time

HOST = "74.91.121.9"
USER = "dodserver"
PASS = "ktp"
PORT = "27019"
INSTANCE = "dodserver5"


def run(ssh, cmd, timeout=30, label=None):
    if label:
        print(f"=== {label} ===")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    if out:
        print(out)
    if err and not any(skip in err for skip in ["No such", "Pseudo-terminal"]):
        print(f"[stderr] {err}", file=sys.stderr)
    return out, err


def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username=USER, password=PASS, timeout=30)

    # 1. Player count check via RCON status.
    print("=== Checking ATL5 player count ===")
    out, _ = run(ssh,
        f"~/dod-{PORT}/{INSTANCE} send 'status' 2>/dev/null; sleep 0.5; tail -20 ~/dod-{PORT}/log/console/console.log | grep -E 'players|map|hostname' | tail -5",
        timeout=15)

    # Parse status output for players count.
    # GoldSrc status format includes: "players : N (max)" or similar.
    players = None
    for line in out.splitlines():
        if "players" in line.lower():
            # Try to extract count.
            import re
            m = re.search(r"(\d+)\s*(?:active|of|players|/)", line, re.IGNORECASE)
            if m:
                players = int(m.group(1))
                break

    if players is None:
        # Fallback: check for any non-empty IDs in tmux status query
        # If status didn't dump or no recent log, do a conservative check.
        print(f"  Could not parse player count from log tail; falling back to LinuxGSM details query.")
        out2, _ = run(ssh, f"~/dod-{PORT}/{INSTANCE} details 2>&1 | head -40", timeout=15)
        # LinuxGSM details output has 'Players : N/N' lines sometimes.
        for line in out2.splitlines():
            if "players" in line.lower() and ":" in line:
                import re
                m = re.search(r"(\d+)\s*/\s*\d+", line)
                if m:
                    players = int(m.group(1))
                    break

    if players is None:
        print(f"  Still couldn't determine player count. ABORTING restart for safety.")
        print(f"  Operator: SSH in and check manually:")
        print(f"    ssh dodserver@{HOST}")
        print(f"    ~/dod-{PORT}/{INSTANCE} send 'status'")
        print(f"    tail -50 ~/dod-{PORT}/log/console/console.log")
        ssh.close()
        return 2

    print(f"  Player count: {players}")
    if players > 0:
        print(f"  ATL5 has {players} player(s). ABORTING restart — not safe.")
        ssh.close()
        return 3

    # 2. Restart.
    print("\n=== Restarting ATL5 ===")
    run(ssh, f"~/dod-{PORT}/{INSTANCE} restart 2>&1 | tail -30", timeout=120, label="dodserver5 restart")

    # Give it a few seconds to come up.
    time.sleep(8)

    # 3. Verify back up + plugin loaded.
    print("\n=== Post-restart verification ===")
    run(ssh, f"~/dod-{PORT}/{INSTANCE} details 2>&1 | grep -E 'IP|Port|Status' | head -5",
        timeout=15, label="Instance status")

    # Check the active plugin md5 — should match what we SCP'd (.new gets renamed by auto-swap).
    run(ssh,
        f"ls -la ~/dod-{PORT}/serverfiles/dod/addons/ktpamx/plugins/KTPMatchHandler.amxx* 2>&1",
        timeout=15, label="Plugin files")

    # Verify version via rcon amx plugins.
    print("\n=== amx plugins (looking for KTPMatchHandler 0.10.133) ===")
    run(ssh,
        f"~/dod-{PORT}/{INSTANCE} send 'amx plugins' 2>/dev/null; sleep 2; "
        f"tail -50 ~/dod-{PORT}/log/console/console.log | grep -E 'MatchHandler|0\\.10\\.' | head -5",
        timeout=20)

    ssh.close()
    print("\n=== Done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
