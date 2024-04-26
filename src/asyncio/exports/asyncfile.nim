when defined(windows):
    raise newException(LibraryError)
else:
    include ../private/asyncfile_posix


proc new*(T: type AsyncFile, file: File): T
proc new*(T: type AsyncFile, path: string, mode = fmRead): T


proc new*(T: type AsyncFile, file: File): T =
    T.new(file.getOsFileHandle())

proc new*(T: type AsyncFile, path: string, mode = fmRead): T =
    T.new(open(path, mode))

let
    stdinAsync* = AsyncFile.new(stdin)
    stdoutAsync* = AsyncFile.new(stdout)
    stderrAsync* = AsyncFile.new(stderr)