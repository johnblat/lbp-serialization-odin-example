if not exist build mkdir build
set name=writer
odin build src\writer -debug -out:build\%name%.exe -vet-unused -vet-unused-variables -vet-unused-imports -vet-shadowing -subsystem:console
