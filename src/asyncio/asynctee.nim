import ./exports/asynciobase {.all.}

import asyncsync, asyncsync/[lock, event]

type
    AsyncTeeReader* = ref object of AsyncIoBase
        ## Object that allows to clone/tee data when reading it
        ## Meaning that reading from it will both read (and return) from underlying reader, and write the data to the underlying writer
        reader: AsyncIoBase
        writer: AsyncIoBase
    
    AsyncTeeWriter* = ref object of AsyncIoBase
        ## Object that allows to clone data written to it to multiple writers
        writers*: seq[AsyncIoBase]


## AsyncTeeReader procs

proc new*(T: type AsyncTeeReader; reader: AsyncIoBase, writer: AsyncIoBase): T =
    result = T(reader: reader, writer: writer)
    result.init(readLock = reader.readLock, writeLock = nil)

method readAvailableUnlocked(self: AsyncTeeReader, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    result = await self.reader.readAvailableUnlocked(count, cancelFut)
    if result != "":
        discard await self.writer.write(result, cancelFut) # isCancellation a good thing ?


method readChunkUnlocked(self: AsyncTeeReader, cancelFut: Future[void]): Future[string] {.async.} =
    result = await self.reader.readChunkUnlocked(cancelFut)
    if result != "":
        discard await self.writer.write(result, cancelFut)

method close*(self: AsyncTeeReader) =
    self.isClosed = true
    self.cancelled.trigger()
    self.reader.close()
    self.writer.close()


## AsyncTeeWriter procs

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
    self.cancelled.trigger()
    self.isClosed = true
    for w in self.writers:
        w.close()