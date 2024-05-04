import ./exports/asynciobase {.all.}
import ./private/[asynctwoend, buffer]

import asyncsync, asyncsync/[lock, event]

type
    AsyncStream* = ref object of AsyncTwoEnd
        ## An in-memory async buffer
        ## Because it is async (read pending for data), it can be highly subjects to deadlocks
        ## To avoid deadlocks: ensure to a least close writer when finished
        ## Not thread safe
    
    AsyncStreamReader* = ref object of AsyncIoBase
        ## Can't be instantiated directly
        buffer: Buffer
        hasData: Event
        writerClosed: ref bool

    AsyncStreamWriter* = ref object of AsyncIoBase
        ## Can't be instantiated directly
        buffer: Buffer
        hasData: Event
        writerClosed: ref bool

    AsyncString* = ref object of AsyncStreamReader
        ## Immutable async stream/buffer, that can only be written at instantiation

proc new(T: type AsyncStreamReader, buffer: Buffer, hasData: Event, writerClosed: ref bool): T =
    result = T(buffer: buffer, hasData: hasData, writerClosed: writerClosed)
    result.init(readLock = Lock.new(), writeLock = nil)

proc new(T: type AsyncStreamWriter, buffer: Buffer, hasData: Event, writerClosed: ref bool): T =
    result = T(buffer: buffer, hasData: hasData, writerClosed: writerClosed)
    result.init(readLock = nil, writeLock = Lock.new())

proc new*(T: type AsyncStream): T =
    var
        buffer = Buffer.new()
        hasData = Event.new()
        writerClosed = new bool
    result = T()
    result.init(
        reader = AsyncStreamReader.new(buffer, hasData, writerClosed),
        writer = AsyncStreamWriter.new(buffer, hasData, writerClosed)
    )

proc new*(T: type AsyncString, data: varargs[string]): AsyncString =
    var stream = AsyncStream.new()
    for chunk in data:
        discard stream.writeUnlocked(chunk, nil)
    stream.writer.close()
    return cast[AsyncString](stream.reader)

proc reader*(self: AsyncStream): AsyncStreamReader = (procCall self.AsyncTwoEnd.reader()).AsyncStreamReader
proc writer*(self: AsyncStream): AsyncStreamWriter = (procCall self.AsyncTwoEnd.writer()).AsyncStreamWriter
proc bufLen*(self: AsyncStream): int = self.reader.buffer.len()
proc bufLen*(self: AsyncStreamReader): int = self.buffer.len()
proc bufLen*(self: AsyncStreamWriter): int = self.buffer.len()


method readAvailableUnlocked(self: AsyncStreamReader, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    if self.closed:
        return
    if not self.writerClosed[]:
        await any(self.hasData.wait(), cancelFut, self.cancelled)
    result = self.buffer.read(count)
    if self.buffer.isEmpty():
        self.hasData.clear()

method readChunkUnlocked(self: AsyncStreamReader, cancelFut: Future[void]): Future[string] {.async.} =
    if self.closed:
        return
    if not self.writerClosed[]:
        await any(self.hasData.wait(), cancelFut, self.cancelled)
        result = self.buffer.readChunk()
        if self.buffer.isEmpty():
            self.hasData.clear()
    else:
        result = self.buffer.readChunk()

method writeUnlocked(self: AsyncStreamWriter, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    if self.closed or self.writerClosed[]:
        return 0
    self.hasData.trigger()
    self.buffer.write(data)
    return data.len()

method close(self: AsyncStreamReader) =
    self.buffer.clear()
    self.closed = true
    self.cancelled.trigger()

method close(self: AsyncStreamWriter) =
    self.closed = true
    self.cancelled.trigger()
    self.hasData.trigger()
    self.writerClosed[] = true