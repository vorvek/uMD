# DOS tests

Install NASM and Python 3.10 or later, then build:

```powershell
python scripts/build.py
```

`MTEST.COM` runs in the guest. It checks the INT 33h functions, the pointer in text mode, mode 13h, and mode 12h, and the VGA registers after a planar draw. It prints `PASS`, or `FAIL`, the test number, and AX BX CX DX. `MTEST /N` expects no driver.

## IzarraVM

```powershell
python scripts/izarra_test.py --emulator D:\dev\izarravm\target\release\izarravm.exe --out E:\tmp\uMD\<session>\iz
python scripts/izarra_test.py --out E:\tmp\uMD\<session>\iz --load-high
```

[IzarraVM](https://github.com/vorvek/izarravm) boots Toka-DOS from a host folder with `UMD.COM` and `MTEST.COM`. The emulator injects PS/2 packets through its keyboard controller at fixed guest times, and `MTEST /W` waits for each one. This covers the motion, the buttons, the sensitivity, and the event handler with real packets. MTEST stops the run through the test port.

## 86Box

```powershell
python scripts/box_test.py --out E:\tmp\uMD\<session>\run
python scripts/box_test.py --out E:\tmp\uMD\<session>\run --load-high
```

The script builds a 32 MiB FAT16 disk with the MS-DOS system files, JEMMEX, and CTMOUSE from the μCDD Battle Chess fixture, boots 86Box with the fixture machine (Pentium II, S3 ViRGE, PS/2 mouse), and reads the results from the disk image. `AUTOEXEC.BAT` installs μMD, changes the sensitivity, runs MTEST, removes μMD, checks that it is gone, installs CTMOUSE, and checks that μMD refuses to install over it. The memory control block chain before and after each driver gives the resident size of both. The run passes when every step passes and μMD is smaller.

The 86Box run skips the motion tests. The Award BIOS of the fixture does not pass bytes that a program writes with 8042 command D3h to the device handler, although IRQ 12 fires and a direct interrupt handler receives them. Real packets reach the handler, which CuteMouse 2.1 beta 4 uses too.

The fixture paths are in `scripts/box_test.py`. The fixture images are not part of this repository.
