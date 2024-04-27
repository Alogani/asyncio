import ../exports/asynciobase {.all.}
import ../exports/asyncfile {.all.} # Don't ./asyncfile_posix, or asyncfile will be efined twice
import std/[posix, os]

type AsyncPipe* = ref object of AsyncIoBase
    reader*: AsyncFile
    writer*: AsyncFile


proc new*(T: type AsyncPipe): T
proc closeWriter*(self: AsyncPipe)
method readAvailableUnlocked(self: AsyncPipe, count: int, cancelFut: Future[void]): Future[string]
method writeUnlocked(self: AsyncPipe, data: string, cancelFut: Future[void]): Future[int]
method close*(self: AsyncPipe)


proc new*(T: type AsyncPipe): T =
    var pipesArr: array[2, cint]
    if pipe(pipesArr) != 0:
        raiseOSError(osLastError())
    let (reader, writer) = (AsyncFile.new(pipesArr[0]), AsyncFile.new(pipesArr[1]))
    result = AsyncPipe(reader: reader, writer: writer)
    result.init(reader.readLock, writer.writeLock)

proc closeWriter*(self: AsyncPipe) =
    ## Writer will be closed, this ensures reader will reach eof
    self.writer.close()

method readAvailableUnlocked(self: AsyncPipe, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    await self.reader.readAvailableUnlocked(count, cancelFut)

method writeUnlocked(self: AsyncPipe, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    await self.writer.writeUnlocked(data, cancelFut)

method close*(self: AsyncPipe) =
    self.reader.close()
    self.writer.close()