import ../exports/asyncfile # Don't ./asyncfile_posix, or asyncfile will be efined twice
import std/[posix, os]

import ./asynctwoend

type AsyncPipe* = ref object of AsyncTwoEnd

proc new*(T: type AsyncPipe): T


proc new*(T: type AsyncPipe): T =
    var pipesArr: array[2, cint]
    if pipe(pipesArr) != 0:
        raiseOSError(osLastError())
    result = T()
    result.init(
        reader = AsyncFile.new(pipesArr[0]),
        writer = AsyncFile.new(pipesArr[1])
    )

proc reader*(self: AsyncPipe): Asyncfile = (procCall self.AsyncTwoEnd.reader()).Asyncfile
proc writer*(self: AsyncPipe): AsyncFile = (procCall self.AsyncTwoEnd.writer()).Asyncfile