# μMD

**Eternal betaware**

μMD (Micro Mouse Driver) is a PS/2 mouse driver for DOS. It is small, it has no acceleration, and it supports the INT 33h functions that DOS programs use. It works well with [μCDD](https://github.com/vorvek/uCDD).

## Requirements

- A 286 or later and DOS 3.3 or later. `LH` needs DOS 5.
- A PS/2 mouse port with BIOS support (INT 15h, AH=C2h). The mouse can have two or three buttons. Serial mice and the wheel are not supported.
- VGA for the pointer in graphics modes. Text modes work on any adapter.

## Setup

Copy `UMD.COM` into a directory and add it to `AUTOEXEC.BAT`:

```dos
LH C:\UMD\UMD.COM
```

Load μMD before μCDD.

## Usage

```text
UMD [/X<n>] [/Y<n>] [/S<n>] [/U]
```

| Option | Effect |
| --- | --- |
| `/X<n>` | Set the horizontal sensitivity to n percent (10 to 400). |
| `/Y<n>` | Set the vertical sensitivity to n percent. |
| `/S<n>` | Set both sensitivities. |
| `/U` | Remove μMD from memory. |

Run `UMD` with `/X`, `/Y`, or `/S` again to change the installed driver. `UMD /?` prints the help. The exit code is 1 when μMD cannot install, finds another mouse driver, or cannot remove itself.

The sensitivity scales the mouse counts before the driver applies the mickey-to-pixel ratio. At 100 percent, μMD moves the pointer like the Microsoft driver: 8 mickeys per 8 virtual pixels horizontally and 16 vertically.

### MOUSTEST

`MOUSTEST.EXE` shows the pointer, the position, the buttons, the mickeys, and the events of the installed driver in text mode and in VGA mode 13h. With μMD installed, the arrow keys change the sensitivity of each axis in steps of 10 percent, and the screen shows the `UMD` options that give the same result.

| Key | Effect |
| --- | --- |
| Left, Right | Horizontal sensitivity down, up |
| Up, Down | Vertical sensitivity up, down |
| M or Tab | Change between text mode and VGA mode |
| R | Set the counters to zero |
| Esc | Quit and print the `UMD` options |

## How it works

`UMD.COM` stays resident. It registers a device handler with the BIOS PS/2 mouse service (INT 15h, AX=C207h) and lets the BIOS own IRQ 12. For each packet, the driver scales the counts, updates the position, the counters, and the pointer, and calls the event handler of the program.

The resident part uses 2,800 bytes, PSP included, or 2,816 bytes with the DOS memory block header. CuteMouse 2.1 beta 4 uses 3,104 bytes measured the same way. The mouse state lives in the unused part of the PSP. The pointer code handles text modes, CGA modes 4 to 6, EGA and VGA modes 0Dh to 12h, and mode 13h.

## Compatibility notes

- INT 33h functions 00h to 26h and 31h. Alternate event handlers (18h, 19h) return an error. The hardware text pointer (0Ah with BX=1) is ignored. Function 13h stores the double-speed threshold but μMD has no acceleration.
- Function 24h reports version 6.26 and mouse type 4 (PS/2).
- The event handler runs on the stack of the interrupted program, like CuteMouse.
- In video modes above 13h the program must draw its own pointer. Programs do this.
- Planar modes need readable VGA registers. On an EGA the registers that the pointer code changes stay changed.

## Build and test

See [BUILDING.md](BUILDING.md) and [tests/README.md](tests/README.md).

## License

GPL-3.0-only. See [LICENSE](LICENSE).
