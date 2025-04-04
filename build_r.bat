if not exist build mkdir build
set name=reader
odin build src\reader -debug -out:build\%name%.exe -vet-unused -vet-unused-variables -vet-unused-imports -vet-shadowing -subsystem:console
