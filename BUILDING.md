# Build from source

Install Python 3 and NASM. Run this command from the source directory:

```console
python scripts/build.py
```

The output files are `build/UMD.COM` (PS/2), `build/UMDCOM.COM` (serial), and `build/MOUSTEST.EXE`. Both drivers come from `src/umd.asm`; `UMDCOM.COM` is assembled with `-DSERIAL=1`. The build also assembles the test programs in `tests/` and prints the size of the resident part of each driver.
