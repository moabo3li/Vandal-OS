set architecture i386:x86-64
set pagination on
set print pretty on
set disassembly-flavor att
set breakpoint pending on

# Temporary entry stop for the current descriptor-state work.
break kernel_main
continue
