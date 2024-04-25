import ./exports/asynciobase {.all.}
import ./private/buffer

const defaultBufSize = 1024 # Is this a good default ?

type
    AsyncBuffer* = ref object of AsyncIoBase
        ## An object that allow to bufferize other AsyncIoBase objects
        ## Slower for local files
        readBuffer: Buffer
        readBufSize: int
        writeBuffer: Buffer
        writeBufSize: int
        stream: AsyncIoBase

proc new*(T: type AsyncBuffer, stream: AsyncIoBase, bufSize = defaultBufSize): T
proc new*(T: type AsyncBuffer, stream: AsyncIoBase, readBufSize, writeBufSize: int): T
proc flush*(self: AsyncBuffer, cancelFut: Future[void] = nil): Future[int]
proc fillBuffer*(self: AsyncBuffer, count: int = 0, cancelFut: Future[void] = nil): Future[int]
proc fillBufferUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void]): Future[int] {.async.}
proc bufLen*(self: AsyncBuffer): tuple[readBuffer, writeBuffer: int]


proc new*(T: type AsyncBuffer, stream: AsyncIoBase, bufSize = defaultBufSize): T =
    return AsyncBuffer.new(stream, bufSize, bufSize)

proc new*(T: type AsyncBuffer, stream: AsyncIoBase, readBufSize, writeBufSize: int): T =
    ## Create a new AsyncBuffer
    ## The buffer will be flushed automatically if bufSize is reached, or never is bufSize == -1
    result = T(
        readBuffer: Buffer.new(), readBufSize: readBufSize,
        writeBuffer: Buffer.new(), writeBufSize: writeBufSize,
        stream: stream)
    result.init(readLock = stream.readLock, writeLock = stream.writeLock)

proc flush*(self: AsyncBuffer, cancelFut: Future[void] = nil): Future[int] =
    var data = self.readBuffer.readAll()
    if data.len() != 0:
        return self.stream.write(data, cancelFut)

proc fillBuffer*(self: AsyncBuffer, count: int = 0, cancelFut: Future[void] = nil): Future[int] {.async.} =
    withLock self.readLock:
        return await self.fillBufferUnlocked(count, cancelFut)

proc fillBufferUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void]): Future[int] {.async.} =
    let data = await self.stream.readUnlocked(if count == 0: self.readBufSize else: count, cancelFut)
    result = data.len()
    self.readBuffer.write(data)

proc bufLen*(self: AsyncBuffer): tuple[readBuffer, writeBuffer: int] =
    (self.readBuffer.len(), self.writeBuffer.len())
 

method readAvailableUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    if self.readBuffer.len() < count:
        discard await self.fillBufferUnlocked(max(count, self.readBufSize), cancelFut)
    return self.readBuffer.read(count)

method readChunkUnlocked(self: AsyncBuffer, cancelFut: Future[void]): Future[string] {.async.} =
    if self.readBuffer.isEmpty():
        return await self.stream.readUnlocked(self.readBufSize, cancelFut)
    else:
        return self.readBuffer.readChunk()

method writeUnlocked(self: AsyncBuffer, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    let dataLen = data.len()
    self.writeBuffer.write(data)
    if self.writeBuffer.len() >= self.writeBufSize:
        return await self.stream.writeUnlocked(self.writeBuffer.readAll(), cancelFut)
    else:
        return dataLen

method closeWhenFlushed*(self: AsyncBuffer) =
    self.stream.closeWhenFlushed()

method close*(self: AsyncBuffer) =
    self.cancelled.trigger()
    self.isClosed = true
    self.stream.close()
