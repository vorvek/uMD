# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Build UMD.COM, MOUSTEST.EXE, and the DOS test programs with NASM."""

from pathlib import Path
import re
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'


def assemble(source, name, listing=False, exe=False):
    BUILD.mkdir(exist_ok=True)
    nasm = shutil.which('nasm')
    if not nasm:
        raise SystemExit('NASM is required.')
    output = BUILD / name
    command = [nasm, '-f', 'bin', '-I', str(ROOT / 'src') + '/', str(ROOT / source), '-o', str(output)]
    if listing:
        command += ['-l', str(output.with_suffix('.lst'))]
    subprocess.run(command, check=True)
    if exe:
        # One code segment at offset 0, a 1 KB stack after the image.
        payload = output.read_bytes()
        size = 32 + len(payload)
        header = struct.pack('<14H', 0x5a4d, size % 512, (size + 511) // 512, 0, 2, 64, 64,
                             (len(payload) + 15) // 16, 1024, 0, 0, 0, 28, 0)
        output.write_bytes(header.ljust(32, bytes(1)) + payload)
    print(f'{name}: {output.stat().st_size} bytes')
    return output


def main():
    output = assemble('src/umd.asm', 'UMD.COM', listing=True)
    listing = output.with_suffix('.lst').read_text()
    match = re.search(r'BA([0-9A-F]{2})([0-9A-F]{2})\s+<1>\s+mov dx, \(resident_end', listing)
    if match:
        paragraphs = int(match[2] + match[1], 16)
        print(f'UMD.COM resident part: {paragraphs * 16} bytes including the PSP')
    assemble('src/moustest.asm', 'MOUSTEST.EXE', exe=True)
    if (ROOT / 'tests').is_dir():
        for source in sorted((ROOT / 'tests').glob('*.asm')):
            assemble(f'tests/{source.name}', source.stem.upper() + '.COM')


if __name__ == '__main__':
    main()
