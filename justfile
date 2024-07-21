set shell := ["bash", "-uc"]

find := "/cygdrive/c/cygwin64/bin/find.exe"
exe := "org-clone.exe"
debug_exe := "org-clone-debug.exe"

debug:
    odin build . -debug -show-timings -out:{{exe}}
    just move_exe

watch:
    watchexec -e odin just debug_watch
	
#ignore
debug_watch:
    #!/bin/sh
    odin build . -debug -out:{{exe}}
    clear
    echo -e '\rok'
    just move_exe

release:
    odin build . -o:speed -show-timings
	
#Line count of project
loc:
	tokei -t Odin -o yaml

fmt:
    #!/bin/sh
    for i in $({{ find }} . -name "*.odin" -type f); do
        odinfmt -w "$i"
    done             

move_exe:
    #!/bin/sh
    mv {{exe}} {{debug_exe}}
