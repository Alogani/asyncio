import ./asyncfile


let
    stdinAsync* = AsyncFile.new(stdin)
    stdoutAsync* = AsyncFile.new(stdout)
    stderrAsync* = AsyncFile.new(stderr)
