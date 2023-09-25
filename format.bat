@echo off

for /R . %%f in (*.odin) do odinfmt -w %%f
