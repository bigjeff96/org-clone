set shell := ["bash", "-uc"]

find := "/cygdrive/c/cygwin64/bin/find.exe"
exe := "org-clone.exe"
debug_exe := "org-clone-debug.exe"

# cool stuff right here baby
debug:
    odin build . -debug -show-timings -out:{{exe}}
    just move_exe

watch:
    watchexec -e odin just debug_watch

debug_watch:
    #!/bin/sh
    odin build . -debug -out:{{exe}}
    clear
    echo -e '\rok'
    just move_exe

release:
    odin build . -o:speed -show-timings

tokei:
	tokei

format:
    #!/bin/sh
    for i in `{{ find }} . -name "*.odin" -type f`; do
        odinfmt -w "$i"
    done             

move_exe:
    #!/bin/sh
    mv {{exe}} {{debug_exe}}
