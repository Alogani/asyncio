import ./exports/asynciobase {.all.}
import ./private/buffer

const defaultBufSize = 1024

type
    AsyncBuffer* = ref object of AsyncIoBase
        ## An object that allow to bufferize other AsyncIoBase objects
        ## Slower for local files
        buf: Buffer
        bufSize: int
        stream: AsyncIoBase

proc new*(T: type AsyncBuffer, stream: AsyncIoBase, bufSize = defaultBufSize): T
proc flush*(self: AsyncBuffer)
proc bufLen*(self: AsyncBuffer): int
method readAvailableUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void]): Future[string]
method readChunkUnlocked(self: AsyncBuffer, cancelFut: Future[void]): Future[string]
method writeUnlocked(self: AsyncBuffer, data: string, cancelFut: Future[void]): Future[int]
method close*(self: AsyncBuffer)


proc new*(T: type AsyncBuffer, stream: AsyncBase, bufSize = defaultBufSize): T =
    ## Create a new AsyncBuffer
    ## The buffer will be flushed automatically if bufSize is reached, or never is bufSize == -1
    result = T(buf: Buffer.new(), bufSize: bufSize, stream: stream)
    result.init(readLock: stream.readLock, writeLock: stream.writeLock)
