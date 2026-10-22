# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Run MTEST /W in IzarraVM with injected PS/2 packets.

  python scripts/build.py
  python scripts/izarra_test.py --emulator D:/dev/izarravm/target/release/izarravm.exe --out E:/tmp/uMD/<session>/iz

IzarraVM boots Toka-DOS from a host folder that holds UMD.COM, MTEST.COM, and
AUTOEXEC.BAT. The emulator sends the mouse packets that MTEST /W waits for,
one every 1.5 guest seconds, and MTEST stops the run through the test port.
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HZ = 166_000_000
FIRST_SECOND = 4
SPACING_SECONDS = 1.5
CYCLES = 40 * HZ
ACTIONS = ['move:16,0', 'move:0,8', 'down', 'up', 'down', 'move:4,0', 'up', 'move:16,0']


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--emulator', type=Path, default=Path('D:/dev/izarravm/target/release/izarravm.exe'))
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--load-high', action='store_true')
    args = parser.parse_args()
    if not str(args.out.resolve()).lower().startswith('e:\\tmp\\'):
        raise SystemExit('Put the run folder under E:\\tmp.')
    work = args.out.resolve()
    work.mkdir(parents=True, exist_ok=True)
    for name in ['UMD.COM', 'MTEST.COM']:
        (work / name).write_bytes((ROOT / 'build' / name).read_bytes())
    high = 'LH ' if args.load_high else ''
    (work / 'AUTOEXEC.BAT').write_bytes(f'@ECHO OFF\r\n{high}UMD\r\nMTEST /W\r\n'.encode())
    schedule = ';'.join(f'{int((FIRST_SECOND + index * SPACING_SECONDS) * HZ)}:{action}'
                        for index, action in enumerate(ACTIONS))
    command = [str(args.emulator), '--hdd-folder', str(work), '--cycles', str(CYCLES), '--inject-mouse', schedule,
               '--expect-test-exit', '--dump-result']
    result = subprocess.run(command, capture_output=True, text=True, errors='replace', timeout=600)
    (work / 'izarravm.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    for line in result.stdout.splitlines():
        if line.startswith('stop:') or 'PASS' in line or 'FAIL' in line or 'uMD' in line:
            print(line.rstrip())
    if result.returncode:
        print(f'IzarraVM exit status {result.returncode}; see {work / "izarravm.log"}')
        sys.exit(1)
    print('PASS: MTEST /W passed in IzarraVM.')


if __name__ == '__main__':
    main()
