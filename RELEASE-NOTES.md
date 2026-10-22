# Beta 0.2.0

## Changes in 0.2.0

- Add `UMDCOM.COM`, a serial mouse driver with the same INT 33h functions and pointer as `UMD.COM`. It drives a Microsoft, Logitech three-button, or Mouse Systems mouse on COM1 to COM4 through the UART interrupt, finds the port and the protocol from the mouse answer, and takes `/C`, `/I`, `/M`, `/3`, and `/Z` for the port, the IRQ, and the protocol. The resident part uses 3,024 bytes.
- Report the mouse type and the IRQ in INT 33h function 24h: CH=4 for PS/2, CH=2 and CL=IRQ for serial.
- `UMD` and `UMDCOM` treat the other μMD driver as another mouse driver and do not change it.
- `MOUSTEST.EXE` shows whether the PS/2 or the serial driver is installed.

# Beta 0.1.0

## Changes in 0.1.0

- First release. PS/2 mouse driver through the BIOS INT 15h C2h services, with INT 33h functions 00h to 26h and 31h.
- Horizontal and vertical sensitivity options `/X`, `/Y`, and `/S`, which also change the installed driver.
- Pointer in text modes, CGA modes 4 to 6, EGA and VGA modes 0Dh to 12h, and mode 13h.
- `MOUSTEST.EXE` to check the driver in text mode and VGA mode and to tune the sensitivity.
