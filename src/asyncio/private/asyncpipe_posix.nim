import ../exports/asynciobase {.all.}
import ../exports/asyncfile {.all.} # Don't ./asyncfile_posix, or asyncfile will be efined twice
import std/[posix, os]

type AsyncPipe* = ref object of AsyncIoBase
    reader*: AsyncFile
    writer*: AsyncFile


proc new*(T: type AsyncPipe): T
method readAvailableUnlocked(self: AsyncPipe, count: int, cancelFut: Future[void]): Future[string]
method writeUnlocked(self: AsyncPipe, data: string, cancelFut: Future[void]): Future[int]
method closeWhenFlushed*(self: AsyncPipe)
method close*(self: AsyncPipe)


proc new*(T: type AsyncPipe): T =
    var pipesArr: array[2, cint]
    if pipe(pipesArr) != 0:
        raiseOSError(osLastError())
    let (reader, writer) = (AsyncFile.new(pipesArr[0]), AsyncFile.new(pipesArr[1]))
    result = AsyncPipe(reader: reader, writer: writer)
    result.init(reader.readLock, writer.writeLock)

method readAvailableUnlocked(self: AsyncPipe, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    await self.reader.readAvailableUnlocked(count, cancelFut)

method writeUnlocked(self: AsyncPipe, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    await self.writer.writeUnlocked(data, cancelFut)

method closeWhenFlushed*(self: AsyncPipe) =
    ## Writer will be closed, and reader only when EOF is reached
    ## if reader is not read completly, it will result in file descriptor leak
    self.reader.closeWhenFlushed()
    self.writer.close()

method close*(self: AsyncPipe) =
    self.reader.close()
    self.writer.close()