set shell := ["bash", "-uc"]

find := "/cygdrive/c/cygwin64/bin/find.exe"

# cool stuff right here baby
debug:
    odin build . -debug -show-timings

watch:
    watchexec -e odin just debug_watch

debug_watch:
    @odin build . -debug
    @-clear
    @echo -e '\rok'

release:
    odin build . -o:speed -show-timings

tokei:
    tokei

format:
    #!/bin/sh
    for i in `{{ find }} . -name "*.odin" -type f`; do
        odinfmt -w "$i"
    done			 
