# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Run the uMD guest tests in 86Box and measure the resident size.

  python scripts/build.py
  python scripts/box_test.py --out E:/tmp/uMD/<session>/run [--load-high] [--seconds 150]
  python scripts/box_test.py --out E:/tmp/uMD/<session>/run --mouse msserial

The run folder gets a 32 MiB FAT16 disk with the MS-DOS system files, JEMMEX,
and CTMOUSE from the uCDD Battle Chess fixture, plus the driver and the test
programs. AUTOEXEC.BAT installs uMD, runs MTEST, removes uMD, checks that it
is gone, installs CTMOUSE, and tries uMD again. The memory control block
chain after each installation gives the resident size of both drivers.

--mouse selects the 86Box mouse and the driver: ps2 runs UMD.COM; msserial,
ltserial, and mssystems put that serial mouse on COM1 and run UMDCOM.COM,
then MTEST /L sends the motion test packets through the UART in loopback
mode.
"""

import argparse
import json
import re
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dos_disk import Fat16  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = Path('E:/tmp/uCDD/local/battle-chess')
SYSTEM = Path('E:/tmp/uMD/local/dos')
BOX = Path('D:/86box/86Box.exe')
ROMS = Path('D:/86box/roms')
WATCHDOG = ROOT / 'scripts' / 'box_watchdog.ps1'
SYSTEM_FILES = ['IO.SYS', 'MSDOS.SYS', 'COMMAND.COM', 'JEMMEX.EXE', 'CTMOUSE.EXE']
CYLINDERS = 65
# 86Box mouse type: driver, install options, MTEST loopback option, CTMOUSE
# options, and the device section of 86box.cfg.
MICE = {
    'ps2': dict(driver='UMD', options='', loop='', ctmouse='', section=''),
    'msserial': dict(driver='UMDCOM', options='', loop='M', ctmouse='',
                     section='[Microsoft Serial Mouse]\nport = 0\nbuttons = 2\n'),
    'ltserial': dict(driver='UMDCOM', options='', loop='3', ctmouse='',
                     section='[Logitech Serial Mouse]\nport = 0\nbuttons = 3\nrts_toggle = 1\n'),
    'mssystems': dict(driver='UMDCOM', options=' /Z', loop='Z', ctmouse=' /M',
                      section='[Mouse Systems Serial Mouse]\nport = 0\nbuttons = 3\n'),
}


def extract_system():
    """Copy the DOS system files out of the fixture image. The image is only read."""
    SYSTEM.mkdir(parents=True, exist_ok=True)
    with (FIXTURE / 'chess.img').open('rb') as image:
        head = image.read(64 * 1024 * 1024)
    disk = Fat16(head)
    for name in SYSTEM_FILES:
        (SYSTEM / name).write_bytes(disk.read(name))
    (SYSTEM / 'boot.bin').write_bytes(head[:disk.start + 512])


def make_image(work, load_high, mouse):
    if not (SYSTEM / 'boot.bin').exists():
        extract_system()
    driver = MICE[mouse]['driver']
    install = driver + MICE[mouse]['options']
    disk = Fat16.format((SYSTEM / 'boot.bin').read_bytes(), CYLINDERS * 16 * 63, 8)
    for name in SYSTEM_FILES:
        disk.add(name, (SYSTEM / name).read_bytes())
    disk.add('CONFIG.SYS', b'DOS=HIGH,UMB\r\nDEVICE=C:\\JEMMEX.EXE\r\n'
                           b'SHELL=C:\\COMMAND.COM C:\\ /E:1024 /P\r\n')
    for name in [driver + '.COM', 'MTEST.COM', 'MEMFREE.COM', 'MCB.COM']:
        disk.add(name, (ROOT / 'build' / name).read_bytes())
    high = 'LH ' if load_high else ''
    bat = ['@ECHO OFF', 'MEMFREE > M0.TXT', 'MCB > MCB0.BIN',
           f'{high}{install} > INSTALL.TXT', 'IF ERRORLEVEL 1 GOTO FAIL',
           'MEMFREE > M1.TXT', 'MCB > MCB1.BIN',
           f'{driver} /X150 /Y80 > CHANGE.TXT', 'IF ERRORLEVEL 1 GOTO FAIL',
           f'{driver} /S100 > CHANGE2.TXT', 'IF ERRORLEVEL 1 GOTO FAIL',
           'MTEST > MTEST.TXT', 'IF ERRORLEVEL 1 GOTO FAIL']
    if MICE[mouse]['loop']:
        bat += [f'MTEST /L{MICE[mouse]["loop"]} > MTESTL.TXT', 'IF ERRORLEVEL 1 GOTO FAIL']
    bat += [f'{driver} /U > REMOVE.TXT', 'IF ERRORLEVEL 1 GOTO FAIL',
           'MEMFREE > M2.TXT',
           'MTEST /N > MTEST2.TXT', 'IF ERRORLEVEL 1 GOTO FAIL', 'MCB > MCB2.BIN',
           f'{high}CTMOUSE{MICE[mouse]["ctmouse"]} > CTMOUSE.TXT', 'MEMFREE > M3.TXT', 'MCB > MCB3.BIN',
           f'{install} > SECOND.TXT', 'IF NOT ERRORLEVEL 1 GOTO FAIL',
           'ECHO PASS > RESULT.TXT', 'GOTO END', ':FAIL', 'ECHO FAIL > RESULT.TXT', ':END']
    disk.add('AUTOEXEC.BAT', ('\r\n'.join(bat) + '\r\n').encode())
    (work / 'disk.img').write_bytes(disk.image)
    cfg = (FIXTURE / '86box.cfg').read_text(encoding='utf-8-sig')
    cfg = re.sub(r'(?m)^hdd_01_fn = .*$', 'hdd_01_fn = disk.img', cfg)
    cfg = re.sub(r'(?m)^hdd_01_parameters = .*$', f'hdd_01_parameters = 63, 16, {CYLINDERS}, 0, ide', cfg)
    cfg = re.sub(r'(?m)^mouse_type = .*$', f'mouse_type = {mouse}', cfg)
    if 'sound_muted' not in cfg:
        cfg = cfg.replace('[General]', '[General]\nsound_muted = 1', 1)
    cfg += '\n' + MICE[mouse]['section']
    (work / '86box.cfg').write_text(cfg)
    shutil.copytree(FIXTURE / 'nvr', work / 'nvr', dirs_exist_ok=True)


def read(image, name):
    try:
        return Fat16(image.read_bytes()).read(name)
    except Exception:
        return None


def run_box(work, seconds):
    box = subprocess.Popen([str(BOX), '-P', str(work), '-R', str(ROMS), '-N'])
    subprocess.Popen(['powershell.exe', '-NoProfile', '-WindowStyle', 'Hidden', '-File', str(WATCHDOG),
                      '-TargetPid', str(box.pid), '-ExpectedPath', str(BOX), '-Seconds', '290'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    start = time.monotonic()
    try:
        while time.monotonic() - start < seconds and box.poll() is None:
            time.sleep(3)
            if read(work / 'disk.img', 'RESULT.TXT'):
                time.sleep(3)
                break
    finally:
        if box.poll() is None:
            box.kill()
        box.wait()
    return round(time.monotonic() - start)


def memfree(data):
    words = data.decode(errors='replace').split()
    return dict(total=int(words[1], 16) * 16, largest=int(words[3], 16) * 16)


def allocated(data):
    """Bytes in use in the memory control block chain, MCB headers included."""
    total = 0
    for offset in range(0, len(data) - len(data) % 18, 18):
        segment, kind, owner, paragraphs = struct.unpack_from('<HBHH', data, offset)
        if owner:
            total += paragraphs * 16 + 16
    return total


def text(image, name):
    data = read(image, name)
    return data.decode(errors='replace').strip() if data else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--load-high', action='store_true', help='Load both drivers with LH.')
    parser.add_argument('--mouse', choices=sorted(MICE), default='ps2', help='86Box mouse type and driver.')
    parser.add_argument('--seconds', type=int, default=150)
    args = parser.parse_args()
    if not str(args.out.resolve()).lower().startswith('e:\\tmp\\'):
        raise SystemExit('Put the run folder under E:\\tmp.')
    work = args.out.resolve()
    if work.exists():
        raise SystemExit(f'The run folder exists; remove it first: {work}')
    work.mkdir(parents=True)
    make_image(work, args.load_high, args.mouse)
    elapsed = run_box(work, min(args.seconds, 280))
    image = work / 'disk.img'
    report = dict(mouse=args.mouse, driver=MICE[args.mouse]['driver'], elapsed_seconds=elapsed,
                  result=text(image, 'RESULT.TXT') or 'NO_RESULT')
    for name in ['INSTALL', 'CHANGE', 'CHANGE2', 'MTEST', 'MTESTL', 'REMOVE', 'MTEST2', 'CTMOUSE', 'SECOND']:
        report[name.lower()] = text(image, name + '.TXT')
    memory = {name: read(image, name + '.TXT') for name in ['M0', 'M1', 'M2', 'M3']}
    if all(memory.values()):
        m = {name: memfree(data) for name, data in memory.items()}
        report.update(conventional_before=m['M0']['total'], umd_conventional_cost=m['M0']['total'] - m['M1']['total'],
                      after_remove=m['M2']['total'], ctmouse_conventional_cost=m['M2']['total'] - m['M3']['total'])
    chains = {name: read(image, name + '.BIN') for name in ['MCB0', 'MCB1', 'MCB2', 'MCB3']}
    if all(chains.values()):
        used = {name: allocated(data) for name, data in chains.items()}
        report.update(umd_resident_bytes=used['MCB1'] - used['MCB0'],
                      ctmouse_resident_bytes=used['MCB3'] - used['MCB2'])
    report['passed'] = (report['result'] == 'PASS' and
                        report.get('umd_resident_bytes', 1 << 20) < report.get('ctmouse_resident_bytes', 0))
    (work / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    if not report['passed']:
        raise SystemExit('FAIL')
    print('PASS: the tests pass and uMD is smaller than CuteMouse.')


if __name__ == '__main__':
    main()
