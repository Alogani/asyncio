import std/deques
import ./exports/asynciobase {.all.}
import ./private/buffer

import asyncsync, asyncsync/[lock, event]

type AsyncChainReader* = ref object of AsyncIoBase
    ## An object that allows to read each stream one after another in order
    readers: Deque[AsyncIoBase]


proc new*(T: type AsyncChainReader, readers: varargs[AsyncIoBase]): T =
    result = T(readers: readers.toDeque())
    var allReaderLocks = newSeqOfCap[Lock](readers.len())
    for r in readers:
        allReaderLocks.add(r.readLock)
    result.init(readLock = allReaderLocks.merge(), writeLock = nil)

proc addReader*(self: AsyncChainReader, readers: varargs[AsyncIoBase]) =
    if self.closed:
        self.closed = false
        self.cancelled.clear()
    for r in readers:
        self.readers.addLast r

method readAvailableUnlocked(self: AsyncChainReader, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    while result == "":
        if self.readers.len() == 0:
            self.close()
            return ""
        result = await self.readers[0].readUnlocked(count, cancelFut)
        if cancelFut != nil and cancelFut.finished():
            return ""
        if result == "":
            discard self.readers.popFirst()

method readChunkUnlocked(self: AsyncChainReader, cancelFut: Future[void]): Future[string] {.async.} =
    while result == "":
        if self.readers.len() == 0:
            self.close()
            return ""
        result = await self.readers[0].readChunkUnlocked(cancelFut)
        if cancelFut != nil and cancelFut.finished():
            return ""
        if result == "":
            discard self.readers.popFirst()

method close(self: AsyncChainReader) =
    self.cancelled.trigger()
    self.closed = true
    for stream in self.readers:
        stream.close()
