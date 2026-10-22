# μMD

**Eternal betaware**

μMD (Micro Mouse Driver) is a tiny PS/2 mouse driver for DOS. It works well with [μCDD](https://github.com/vorvek/uCDD).

## Requirements

- A 286 or later and DOS 3.3 or later. `LH` needs DOS 5.
- A PS/2 mouse port with BIOS support (INT 15h, AH=C2h). Two or three buttons are supported.

## Setup

Copy `UMD.COM` into a directory and add it to `AUTOEXEC.BAT`. Can be safely loaded high.

```dos
LH C:\UMD\UMD.COM
```

If using it with μCDD, load the mouse driver first. The resident part uses 2,800 bytes.

## Usage

```text
UMD [/X<n>] [/Y<n>] [/S<n>] [/U]
```

| Option | Effect |
| --- | --- |
| `/X<n>` | Set the horizontal sensitivity to n percent (10 to 400). |
| `/Y<n>` | Set the vertical sensitivity to n percent. |
| `/S<n>` | Set the same sensitivity for both axes. |
| `/U` | Remove μMD from memory. |

Run `UMD` with `/X`, `/Y`, or `/S` again to change the installed driver. `UMD /?` prints the help.

## MOUSTEST

`MOUSTEST.EXE` is a small debug tool used to see if the driver is actually working, and will allow you to fine tune your mouse sensitivity. It doesn't override it, but will give you the values you have to pass as arguments.

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
