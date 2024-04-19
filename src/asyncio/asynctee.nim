import ./exports/asynciobase {.all.}

type
    AsyncTeeReader* = ref object of AsyncIoBase
        ## Reading from it, tees the output to a writer
        reader: AsyncIoBase
        writer: AsyncIoBase
    
    AsyncTeeWriter* = ref object of AsyncIoBase
        ## Allows to write to multiple readers
        writers*: seq[AsyncIoBase]


proc new*(T: type AsyncTeeReader; reader: AsyncIoBase, writer: AsyncIoBase): T
method readAvailableUnlocked(self: AsyncTeeReader, count: int, cancelFut: Future[void]): Future[string]
method readChunkUnlocked(self: AsyncTeeReader, cancelFut: Future[void]): Future[string]
method close*(self: AsyncTeeReader)
proc new*(T: type AsyncTeeWriter, writers: varargs[AsyncIoBase]): T
method writeUnlocked(self: AsyncTeeWriter, data: string, cancelFut: Future[void] = nil): Future[int]
method close*(self: AsyncTeeWriter)


proc new*(T: type AsyncTeeReader; reader: AsyncIoBase, writer: AsyncIoBase): T =
    result = T(reader: reader, writer: writer)
    result.init(readLock = reader.readLock and writer.writeLock, writeLock = nil)

method readAvailableUnlocked(self: AsyncTeeReader, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    result = await self.reader.readAvailableUnlocked(count, cancelFut)
    if result != "":
        discard await self.writer.writeUnlocked(result, nil) # Warning : no cancelation possible to avoid unexpected behaviour

method readChunkUnlocked(self: AsyncTeeReader, cancelFut: Future[void]): Future[string] {.async.} =
    result = await self.reader.readChunkUnlocked(cancelFut)
    if result != "":
        discard await self.writer.writeUnlocked(result, nil) # Warning : no cancelation possible to avoid unexpected behaviour


method close*(self: AsyncTeeReader) =
    self.reader.close()


proc new*(T: type AsyncTeeWriter, writers: varargs[AsyncIoBase]): T =
    result = T(writers: @writers)
    var allWriteLocks = newSeqOfCap[Lock](writers.len())
    for w in writers:
        allWriteLocks.add(w.writeLock)
    result.init(readLock = nil, writeLock = allWriteLocks.merge())

method writeUnlocked(self: AsyncTeeWriter, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    var allFuts = newSeqOfCap[Future[int]](self.writers.len())
    for w in self.writers:
        allFuts.add(w.writeUnlocked(data, cancelFut))
    for res in (await all(allFuts)):
        result += res

method close*(self: AsyncTeeWriter) =
    for writer in self.writers:
        writer.close()
