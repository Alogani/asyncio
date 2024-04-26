import ./exports/asynciobase {.all.}
import ./private/buffer


type AsyncStream* = ref object of AsyncIoBase
    ## An in-memory async buffer
    ## Because it is async (read pending for data), it can be highly subjects to deadlocks
    ## To avoid deadlocks: ensure there is always one writer and to close AsyncStream if there is no more writers
    buffer: Buffer
    hasData: Event
    writeClosed: bool

proc new*(T: type AsyncStream): T
proc bufLen*(self: AsyncStream): int
method readAvailableUnlocked(self: AsyncStream, count: int, cancelFut: Future[void]): Future[string]
method readChunkUnlocked(self: AsyncStream, cancelFut: Future[void]): Future[string]
method writeUnlocked(self: AsyncStream, data: string, cancelFut: Future[void]): Future[int]
method closeWhenFlushed*(self: AsyncStream) {.gcsafe.}
method close*(self: AsyncStream) {.gcsafe.}

proc new*(T: type AsyncStream): T =
    result = T(buffer: Buffer.new(), hasData: Event.new())
    result.init(readLock = Lock.new(), writeLock = Lock.new())

proc bufLen*(self: AsyncStream): int =
    return self.buffer.len()

method readAvailableUnlocked(self: AsyncStream, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    if self.isClosed:
        return
    if self.writeClosed:
        if self.buffer.isEmpty():
            self.close()
            return
    else:
        await any(self.hasData.wait(), cancelFut, self.cancelled)
    result = self.buffer.read(count)
    if self.buffer.isEmpty():
        self.hasData.clear()

method readChunkUnlocked(self: AsyncStream, cancelFut: Future[void]): Future[string] {.async.} =
    if self.isClosed:
        return
    if self.writeClosed:
        if self.buffer.isEmpty():
            self.close()
            return
    else:
        await any(self.hasData.wait(), cancelFut, self.cancelled)
    result = self.buffer.readChunk()
    if self.buffer.isEmpty():
        self.hasData.clear()

method writeUnlocked(self: AsyncStream, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    if self.isClosed or self.writeClosed:
        return 0
    self.hasData.trigger()
    self.buffer.write(data)
    return data.len()

method closeWhenFlushed*(self: AsyncStream) =
    if self.buffer.isEmpty():
        self.close()
    else:
        self.writeClosed = true

method close*(self: AsyncStream) =
    self.buffer.clear()
    self.isClosed = true
    self.cancelled.trigger()
