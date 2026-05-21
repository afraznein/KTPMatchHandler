"""Read-only player check on ATL:27019.

Counts active UDP connections + queries via rcon if reachable. No server-state
changes. Used to confirm the instance is empty before a stop/start cycle.
"""
import io
import re
import sys
import paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

HOST = '74.91.121.9'
USER = 'dodserver'
PASS = 'ktp'
PORT_DIR = 'dod-27019'


def run(ssh, cmd, timeout=30):
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    return (
        stdout.channel.recv_exit_status(),
        stdout.read().decode('utf-8', errors='replace').rstrip(),
        stderr.read().decode('utf-8', errors='replace').rstrip(),
    )


ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, username=USER, password=PASS, timeout=15)

print('=== ATL:27019 player check ===\n')

# 1. Confirm process is running first
_, pgrep_out, _ = run(ssh, "pgrep -af 'hlds_linux.*-port 27019' || echo NO_PROCESS")
print(f'Process check:\n  {pgrep_out}\n')

# 2. LinuxGSM details for player count (lightweight, no side effects)
_, det_out, _ = run(ssh, f'cd ~/{PORT_DIR} && ./dodserver5 details 2>&1 | grep -E "Players|Status|Hostname|Map" | head -10')
print(f'LinuxGSM details:\n{det_out}\n')

# 3. status command via runtime tmux send + tail of console log (capture rcon output)
#    Send "status" via the LinuxGSM send wrapper, then tail the console.
run(ssh, f'cd ~/{PORT_DIR} && ./dodserver5 send status')
import time
time.sleep(1.5)
_, status_out, _ = run(ssh, f'tail -60 ~/{PORT_DIR}/log/console/console.log | sed -n "/^hostname:/,/^#end/p" | head -40')
if not status_out:
    # fallback: just last 30 lines
    _, status_out, _ = run(ssh, f'tail -30 ~/{PORT_DIR}/log/console/console.log')

print('Recent console (post `status`):\n' + status_out)

# 4. Parse player count from "players :" line if present
m = re.search(r'players\s*:\s*(\d+)\s+active', status_out)
if m:
    n = int(m.group(1))
    print(f'\n>>> ACTIVE PLAYERS: {n}')
    if n == 0:
        print('>>> SAFE TO STOP/RESTART')
    else:
        print('>>> NOT SAFE — players present')
else:
    print('\n>>> Could not parse players line; inspect console output above')

ssh.close()
