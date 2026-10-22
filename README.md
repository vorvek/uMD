# μMD

**Eternal betaware**

μMD (Micro Mouse Driver) is a small PS/2 mouse driver for DOS. No acceleration, no serial mice, no wheel. It works well with [μCDD](https://github.com/vorvek/uCDD).

## Requirements

- A 286 or later and DOS 3.3 or later. `LH` needs DOS 5.
- A PS/2 mouse port with BIOS support (INT 15h, AH=C2h). Two or three buttons.
- VGA for the pointer in graphics modes. Text modes work on any adapter.

## Setup

Copy `UMD.COM` into a directory and add it to `AUTOEXEC.BAT`:

```dos
LH C:\UMD\UMD.COM
```

Load μMD before μCDD. The resident part uses 2,800 bytes.

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

Run `UMD` with `/X`, `/Y`, or `/S` again to change the installed driver. `UMD /?` prints the help.

## MOUSTEST

`MOUSTEST.EXE` shows the pointer, the position, the buttons, the mickeys, and the events of the installed driver in text mode and in VGA mode 13h. With μMD installed, the arrow keys change the sensitivity of each axis, and the screen shows the `UMD` options that give the same result.

| Key | Effect |
| --- | --- |
| Left, Right | Horizontal sensitivity down, up |
| Up, Down | Vertical sensitivity up, down |
| M or Tab | Change between text mode and VGA mode |
| R | Set the counters to zero |
| Esc | Quit and print the `UMD` options |

## Build

See [BUILDING.md](BUILDING.md) and [tests/README.md](tests/README.md).

## License

GPL-3.0-only. See [LICENSE](LICENSE).
