import std/deques
import ./exports/asynciobase {.all.}
import ./private/buffer

type AsyncChainReader* = ref object of AsyncIoBase
    readers*: Deque[AsyncIoBase]


proc new*(T: type AsyncChainReader, readers: varargs[AsyncIoBase]): T
method readAvailableUnlocked(self: AsyncChainReader, count: int, cancelFut: Future[void]): Future[string]
method readChunkUnlocked(self: AsyncChainReader, cancelFut: Future[void]): Future[string]


proc new*(T: type AsyncChainReader, readers: varargs[AsyncIoBase]): T =
    result = T(readers: readers.toDeque())
    var allReaderLocks = newSeqOfCap[Lock](readers.len())
    for r in readers:
        allReaderLocks.add(r.readLock)
    result.init(readLock = allReaderLocks.merge(), writeLock = nil)


method readAvailableUnlocked(self: AsyncChainReader, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    while result == "":
        if self.readers.len() == 0:
            return ""
        result = await self.readers[0].readUnlocked(count, cancelFut)
        if cancelFut != nil and cancelFut.finished():
            return ""
        if result == "":
            discard self.readers.popFirst()

method readChunkUnlocked(self: AsyncChainReader, cancelFut: Future[void]): Future[string] {.async.} =
    while result == "":
        if self.readers.len() == 0:
            return ""
        result = await self.readers[0].readChunkUnlocked(cancelFut)
        if cancelFut != nil and cancelFut.finished():
            return ""
        if result == "":
            discard self.readers.popFirst()
