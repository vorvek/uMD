# Beta 0.1.0

## Changes in 0.1.0

- First release. PS/2 mouse driver through the BIOS INT 15h C2h services, with INT 33h functions 00h to 26h and 31h.
- Horizontal and vertical sensitivity options `/X`, `/Y`, and `/S`, which also change the installed driver.
- Pointer in text modes, CGA modes 4 to 6, EGA and VGA modes 0Dh to 12h, and mode 13h.
- `MOUSTEST.EXE` to check the driver in text mode and VGA mode and to tune the sensitivity.
