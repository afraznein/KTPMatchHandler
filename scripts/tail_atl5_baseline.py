"""Stream ATL5 console log filtered for spray-baseline-relevant events.

Runs `tail -F` over SSH and prints any line matching the relevant grep
filter to stdout (one line at a time, line-buffered). Designed for
foreground use in a background bash slot so the harness can monitor
new stdout lines as they arrive.
"""
import paramiko
import sys

HOST = "74.91.121.9"
USER = "dodserver"
PASS = "ktp"
LOG = "/home/dodserver/dod-27019/log/console/dodserver5-console.log"

# Match AC weapon-timeline events + baseline synth + any error/bad-load.
# Egrep is line-buffered with --line-buffered.
PATTERN = "AC_BASELINE_MATCH_ID_SYNTH|AC_WEAPON_TIMELINE_SEND|AC_ERROR|bad load|KTPMatchHandler.*event=PLUGIN_ENABLED|MATCH_START|MATCH_END"

# stdbuf -oL forces line-buffered stdout end-to-end, even when PTY/buffering
# behavior is flaky across the SSH channel. -n 200 backfills any events that
# happened in the ~seconds between the previous tail dying and this one
# starting (e.g. across the server restart that activates the new plugin).
REMOTE_CMD = f"stdbuf -oL tail -F -n 200 {LOG} | stdbuf -oL grep --line-buffered -E '{PATTERN}'"


def main():
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username=USER, password=PASS, timeout=30)

    print(f"[tail] watching {LOG} for: {PATTERN}", flush=True)

    transport = ssh.get_transport()
    transport.set_keepalive(30)

    channel = transport.open_session()
    channel.get_pty()  # forces line-buffering on the remote side
    channel.exec_command(REMOTE_CMD)

    buf = ""
    while True:
        if channel.recv_ready():
            data = channel.recv(4096).decode("utf-8", errors="replace")
            buf += data
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                line = line.rstrip("\r")
                if line:
                    print(line, flush=True)
        elif channel.exit_status_ready():
            break
        else:
            # Block briefly to avoid spinning.
            channel.settimeout(1.0)
            try:
                data = channel.recv(4096).decode("utf-8", errors="replace")
                if data:
                    buf += data
            except Exception:
                pass

    ssh.close()


if __name__ == "__main__":
    main()
