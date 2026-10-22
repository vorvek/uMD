# Build from source

Install Python 3 and NASM. Run this command from the source directory:

```console
python scripts/build.py
```

The output files are `build/UMD.COM` and `build/MOUSTEST.EXE`. The build also assembles the test programs in `tests/` and prints the size of the resident part.
