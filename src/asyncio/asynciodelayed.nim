import ./exports/asynciobase {.all.}

type AsyncIoDelayed* = ref object of AsyncIoBase
    ## An object that permits to add a delay before each read or write is executed
    stream: AsyncIoBase
    delayMs: float


proc new*(T: type AsyncIoDelayed; stream: AsyncIoBase, delayMs: float): T =
    result = T(stream: stream, delayMs: delayMs)
    result.init(readLock = stream.readLock, writeLock = stream.writeLock)


method readAvailableUnlocked(self: AsyncIoDelayed, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    await sleepAsync(self.delayMs)
    return await self.stream.readAvailableUnlocked(count, cancelFut)

method readChunkUnlocked(self: AsyncIoDelayed, cancelFut: Future[void]): Future[string] {.async.} =
    await sleepAsync(self.delayMs)
    return await self.stream.readChunkUnlocked(cancelFut)

method writeUnlocked(self: AsyncIoDelayed, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    await sleepAsync(self.delayMs)
    return await self.stream.writeUnlocked(data, cancelFut)

method closeWhenFlushed*(self: AsyncIoDelayed) =
    self.stream.closeWhenFlushed()

method close*(self: AsyncIoDelayed) =
    self.cancelled.trigger()
    self.isClosed = true
    self.stream.close()