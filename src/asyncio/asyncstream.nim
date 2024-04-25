import ./exports/asynciobase {.all.}
import ./private/buffer

## Careful of deadlocks:
##  - when AsyncStream is not closed
##  - and there is no writers anymore

type AsyncStream* = ref object of AsyncIoBase
    buf: Buffer
    hasData: Event

proc new*(T: type AsyncStream): T
proc bufLen*(self: AsyncStream): int
method readAvailableUnlocked(self: AsyncStream, count: int, cancelFut: Future[void]): Future[string]
method readChunkUnlocked(self: AsyncStream, cancelFut: Future[void]): Future[string]
method writeUnlocked(self: AsyncStream, data: string, cancelFut: Future[void]): Future[int]
method close*(self: AsyncStream)

proc new*(T: type AsyncStream): T =
    result = T(buf: Buffer.new(), hasData: Event.new())
    result.init(readLock = Lock.new(), writeLock = Lock.new())

proc bufLen*(self: AsyncStream): int =
    return self.buf.len()

method readAvailableUnlocked(self: AsyncStream, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    if not self.isClosed:
        await any(self.hasData.wait(), cancelFut, self.cancelled)
    else:
        if self.buf.isEmpty(): self.cancelled.trigger()
    result = self.buf.read(count)
    if self.buf.isEmpty():
        self.hasData.clear()

method readChunkUnlocked(self: AsyncStream, cancelFut: Future[void]): Future[string] {.async.} =
    if not self.isClosed:
        await any(self.hasData.wait(), cancelFut, self.cancelled)
    else:
        if self.buf.isEmpty(): self.cancelled.trigger()
    result = self.buf.readChunk()
    if self.buf.isEmpty():
        self.hasData.clear()

method writeUnlocked(self: AsyncStream, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    if self.isClosed:
        return 0
    self.hasData.trigger()
    self.buf.write(data)
    return data.len()

method close*(self: AsyncStream) =
    self.hasData.trigger() # Not cancelled.trigger() to allow last reads
    self.isClosed = true