{.warning: "slower than unbuffered reads (on ssd)".}

#[
## THE FOLLOWING TEST SHOWS THAT BUFFERIZED STREAM IS SLOWER
import posix
import mylib/asyncio/internal/buffer
import mylib/testing

var f: File
var buf = Buffer.new()

discard open(f, "random_data.txt")
var fd = f.getOsFileHandle()


#const readSize = 64
for readSize in { 8, 16, 32 }:
    for ratio in 2 .. 8:
        echo "*** READSIZE=", readSize, " ***"
        echo "*** RATIO=", ratio, " ***"

        var bytesRead: int
        var data = newString(readSize * ratio)
        bytesRead = 0
        runBench("buffered"):
            let count = posix.read(fd, addr(data[0]), readSize * ratio)
            data.setLen(count)
            buf.write(data)
            for i in 0 ..< ratio:
                bytesRead += buf.read(readSize).len()
        echo bytesRead

        bytesRead = 0
        data = newString(readSize)
        runBench("unbuffered"):
            for i in 0 ..< ratio:
                discard posix.read(fd, addr(data[0]), readSize)
                bytesRead += data.len()

        echo bytesRead
]#

#[
# Incomplete

import ../asyncbase {.all.}
import ./buffer

const
    Bufsize = 1024

type AsyncBuffer* = ref object of AsyncBase
    ## Serve to bufferize other AsyncObjects
    buf: Buffer
    stream: AsyncBase
    fullyBuffered: bool

proc new*(T: type AsyncBuffer, stream: AsyncBase): T
method readUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void] = nil): Future[string]
method readMostUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void] = nil): Future[string]
method readChunkUnlocked(self: AsyncBuffer, cancelFut: Future[void] = nil): Future[string]
method readLineUnlocked(self: AsyncBuffer, keepNewLine = false, cancelFut: Future[void] = nil): Future[string]
method readAllUnlocked(self: AsyncBuffer, cancelFut: Future[void] = nil): Future[string]
method writeUnlocked(self: AsyncBuffer, data: string, cancelFut: Future[void] = nil): Future[int]
method close*(self: AsyncBuffer)


proc new*(T: type AsyncBuffer, stream: AsyncBase): T =
    result = T(buf: Buffer.new(), stream: stream)
    result.init(readLock: stream.readLock, writeLock: stream.writeLock)

method readUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void] = nil): Future[string] {.async.} =
    result = self.buf.read(count)
    if result.len() == count:
        return
    let data = await self.stream.read(max(Bufsize, count - Bufsize), cancelFut)
    if data == "":
        return
    self.buf.write(data)
    result.add(self.buf.read(result.len() - count))
]#