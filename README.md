# Vandal OS

Vandal OS is a small educational x86-64 kernel written in C. It boots with
Limine and runs on a single CPU in QEMU.

## Current state

The kernel currently:

- builds as a freestanding ELF file with Clang and LLD;
- boots from a Limine ISO;
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
./scripts/run-qemu.sh
```

The first build downloads the pinned Limine release and protocol header, then
verifies their SHA-256 hashes.

Useful commands:

```sh
./scripts/run-qemu.sh --debug  # Start QEMU paused for GDB
make clean        # Remove generated files
```

## Project files

- `kernel/main.c` contains the kernel entry point and halt loop.
- `kernel/linker.ld` defines the ELF memory layout.
- `boot/limine.conf` contains the bootloader configuration.
- `Makefile` builds the kernel and bootable ISO.
- `scripts/run-qemu.sh` starts the kernel in QEMU.

## References

- [Limine boot protocol](https://github.com/limine-bootloader/limine-protocol)
- [Limine C template](https://github.com/limine-bootloader/limine-c-template)
- [Operating System in 1,000 Lines](https://1000os.seiya.me/)

## License

Vandal OS is available under the [MIT License](LICENSE).
