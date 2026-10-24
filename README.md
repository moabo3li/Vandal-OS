# Vandal OS

Vandal OS is a small educational x86-64 kernel written in C. It boots with
Limine and runs on a single CPU in QEMU.

## Current state

The kernel currently:

- builds as a freestanding ELF file with Clang and LLD;
- boots from a pinned and hash-verified Limine ISO;
- validates the Limine base revision and its initialized and zero-filled data;
- initializes COM1 and prints a startup line;
- reports machine-readable test results to QEMU; and
- stops in a `cli; hlt` loop.

Memory management, interrupts, processes, and user space are not implemented
yet. The initial stack and page tables are provided by Limine.

## Tools

- Clang and LLD compile and link the kernel.
- GNU Make manages the build.
- Limine loads the kernel.
- xorriso creates the bootable ISO.
- QEMU runs the kernel.
- GDB supports debugging.

The build also uses curl, sha256sum, and tar to download and verify the pinned
Limine files.

## Build and run

Install the tools above, including `qemu-system-x86_64`, then run:

```sh
make
make run
```

The first build downloads the pinned Limine release and protocol header, then
verifies their SHA-256 hashes.

Useful commands:

```sh
make debug          # Start QEMU paused for GDB
make test-host      # Run deterministic host-side unit tests
make test-qemu      # Run positive and negative guest checks
make test-artifact  # Verify the linked ELF and ISO payload
make test           # Run all automated tests
make check          # Run formatting, scripts, LSP, and all tests
make clean          # Remove generated files
```

The compatibility wrappers `./run.sh` and `./run.sh --debug` invoke the same
Make targets. QEMU execution scripts accept an explicit ISO and do not rebuild
it, so Make remains the single owner of dependency and artifact construction.

Generated files are organized under `build/`: production artifacts at the
top level, shared pinned dependencies in `build/deps`, test variants in
`build/tests`, test logs in `build/test-results`, and clangd's compilation
database in `build/compile_commands.json`.

## Project files

- `kernel/main.c` contains the kernel entry point and halt loop.
- `kernel/linker.ld` defines the ELF memory layout.
- `boot/limine.conf` contains the bootloader configuration.
- `Makefile` builds the kernel and bootable ISO.
- `scripts/run-qemu.sh` executes an explicit ISO in QEMU.
- `scripts/test-guest-result.sh` checks one explicit QEMU test artifact.
- `scripts/verify-artifact.sh` checks ELF and ISO structural invariants.
- `tests/serial_test.c` tests the serial driver with deterministic fake I/O.

## References

- [Limine boot protocol](https://github.com/limine-bootloader/limine-protocol)
- [Limine C template](https://github.com/limine-bootloader/limine-c-template)
- [Operating System in 1,000 Lines](https://1000os.seiya.me/)

## License

Vandal OS is available under the [MIT License](LICENSE).
