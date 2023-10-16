@echo off

odin build . -debug -use-separate-modules -show-timings || exit /b 666
rem start /b remedybg.exe -q open-session 3d_render.rdbg
