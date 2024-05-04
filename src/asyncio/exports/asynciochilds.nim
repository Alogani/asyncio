import ./asynciobase {.all.}
import ../private/buffer

import asyncsync, asyncsync/[lock, event]
import std/deques

import ../private/asynctwoend

# AsyncFile, AsyncPipe
when defined(windows):
    raise newException(LibraryError)
else:
    import ../private/asynciochilds_posix
    export asynciochilds_posix

const defaultAsyncBufferSize* = 1024

type
    AsyncBuffer* = ref object of AsyncIoBase
        ## An object that allow to bufferize other AsyncIoBase objects.
        ## Slower for local files
        stream*: AsyncIoBase
        readBuffer: Buffer
        readBufSize: int
        writeBuffer: Buffer
        writeBufSize: int

    AsyncChainReader* = ref object of AsyncIoBase
        ## An object that allows to read each stream one after another in order
        readers: Deque[AsyncIoBase]

    AsyncIoDelayed* = ref object of AsyncIoBase
        ## An object that permits to add a delay before each read or write is executed
        stream: AsyncIoBase
        delayMs: float

    AsyncStream* = ref object of AsyncTwoEnd
        ## An in-memory async buffer
        ## 
        ## Because it is async (read pending for data), it can be highly subjects to deadlocks.
        ## To avoid deadlocks: ensure to a least close writer when finished.
        ## Not thread safe
    
    AsyncStreamReader* = ref object of AsyncIoBase
        ## Reader object of AsyncStream. Can't be instantiated directly
        buffer: Buffer
        hasData: Event
        writerClosed: ref bool

    AsyncStreamWriter* = ref object of AsyncIoBase
        ## Writer object of AsyncStream. Can't be instantiated directly
        buffer: Buffer
        hasData: Event
        writerClosed: ref bool

    AsyncString* = ref object of AsyncStreamReader
        ## Immutable async stream/buffer, that can only be written at instantiation
        ## 
        ## No deadlock is possible

    AsyncTeeReader* = ref object of AsyncIoBase
        ## Object that allows to clone/tee data when reading it
        ## 
        ## Meaning that reading from it will both read (and return) from underlying reader, and write the data to the underlying writer
        reader: AsyncIoBase
        writer: AsyncIoBase
    
    AsyncTeeWriter* = ref object of AsyncIoBase
        ## Object that allows to clone data written to it to multiple writers
        writers*: seq[AsyncIoBase]

    AsyncVoid* = ref object of AsyncIoBase
        ## Does nothing and can only be written to.
        ## Equivalent of a /dev/null, write to it will do nothing


proc addReader*(self: AsyncChainReader, readers: varargs[AsyncIoBase]) =
    if self.closed:
        self.closed = false
        self.cancelled.clear()
    for r in readers:
        self.readers.addLast r

proc bufLen*(self: AsyncBuffer): tuple[readBuffer, writeBuffer: int] =
    (self.readBuffer.len(), self.writeBuffer.len())

proc bufLen*(self: AsyncStream): int =
    cast[AsyncStreamReader](self.reader).buffer.len()

proc bufLen*(self: AsyncStreamReader): int =
    self.buffer.len()

proc bufLen*(self: AsyncStreamWriter): int =
    self.buffer.len()

proc fillBufferUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void]): Future[int] {.async.} =
    let data = await self.stream.readUnlocked(if count == 0: self.readBufSize else: count, cancelFut)
    result = data.len()
    self.readBuffer.write(data)

proc fillBuffer*(self: AsyncBuffer, count: int = 0, cancelFut: Future[void] = nil): Future[int] {.async.} =
    ## Equivalent to a read but instead of returning data, keep it in its internal memory
    withLock self.readLock:
        return await self.fillBufferUnlocked(count, cancelFut)

proc flush*(self: AsyncBuffer, cancelFut: Future[void] = nil): Future[int] =
    ## Empty all data in the internal memory. it doesn't flush the wrapped stream
    var data = self.readBuffer.readAll()
    if data.len() != 0:
        return self.stream.write(data, cancelFut)

proc new*(T: type AsyncBuffer, stream: AsyncIoBase, bufSize = defaultAsyncBufferSize): T =
    return AsyncBuffer.new(stream, bufSize, bufSize)

proc new*(T: type AsyncBuffer, stream: AsyncIoBase, readBufSize, writeBufSize: int): T =
    ## Create a new AsyncBuffer.
    result = T(
        readBuffer: Buffer.new(), readBufSize: readBufSize,
        writeBuffer: Buffer.new(), writeBufSize: writeBufSize,
        stream: stream)
    result.init(readLock = stream.readLock, writeLock = stream.writeLock)

proc new*(T: type AsyncChainReader, readers: varargs[AsyncIoBase]): T =
    result = T(readers: readers.toDeque())
    var allReaderLocks = newSeqOfCap[Lock](readers.len())
    for r in readers:
        allReaderLocks.add(r.readLock)
    result.init(readLock = allReaderLocks.merge(), writeLock = nil)

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
    ## The stream can only be filled using `data` argument
    var stream = AsyncStream.new()
    for chunk in data:
        discard stream.writeUnlocked(chunk, nil)
    stream.writer.close()
    return cast[AsyncString](stream.reader)

proc new*(T: type AsyncTeeReader; reader: AsyncIoBase, writer: AsyncIoBase): T =
    result = T(reader: reader, writer: writer)
    result.init(readLock = reader.readLock, writeLock = nil)

proc new*(T: type AsyncTeeWriter, writers: varargs[AsyncIoBase]): T =
    result = T(writers: @writers)
    var allWriteLocks = newSeqOfCap[Lock](writers.len())
    for w in writers:
        allWriteLocks.add(w.writeLock)
    result.init(readLock = nil, writeLock = allWriteLocks.merge())

proc new*(T: type AsyncVoid): T =
    result = T()
    result.init(readLock = Lock.new(), writeLock = Lock.new())

proc reader*(self: AsyncStream): AsyncStreamReader =
    (procCall self.AsyncTwoEnd.reader()).AsyncStreamReader

proc writer*(self: AsyncStream): AsyncStreamWriter =
    (procCall self.AsyncTwoEnd.writer()).AsyncStreamWriter

method close(self: AsyncBuffer) =
    self.cancelled.trigger()
    self.closed = true
    self.stream.close()

method close(self: AsyncChainReader) =
    self.cancelled.trigger()
    self.closed = true
    for stream in self.readers:
        stream.close()

method close(self: AsyncIoDelayed) =
    self.cancelled.trigger()
    self.closed = true
    self.stream.close()

method close(self: AsyncStreamReader) =
    self.buffer.clear()
    self.closed = true
    self.cancelled.trigger()

method close(self: AsyncStreamWriter) =
    self.closed = true
    self.cancelled.trigger()
    self.hasData.trigger()
    self.writerClosed[] = true

method close(self: AsyncTeeReader) =
    self.closed = true
    self.cancelled.trigger()
    self.reader.close()
    self.writer.close()

method close(self: AsyncTeeWriter) =
    self.cancelled.trigger()
    self.closed = true
    for w in self.writers:
        w.close()

method close(self: AsyncVoid) =
    self.closed = true

method readAvailableUnlocked(self: AsyncBuffer, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    if self.readBuffer.len() < count:
        discard await self.fillBufferUnlocked(max(count, self.readBufSize), cancelFut)
    return self.readBuffer.read(count)

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

method readAvailableUnlocked(self: AsyncIoDelayed, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    await sleepAsync(self.delayMs)
    return await self.stream.readAvailableUnlocked(count, cancelFut)

method readAvailableUnlocked(self: AsyncStreamReader, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    if self.closed:
        return
    if not self.writerClosed[]:
        await any(self.hasData.wait(), cancelFut, self.cancelled)
    result = self.buffer.read(count)
    if self.buffer.isEmpty():
        self.hasData.clear()

method readAvailableUnlocked(self: AsyncTeeReader, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    result = await self.reader.readAvailableUnlocked(count, cancelFut)
    if result != "":
        discard await self.writer.write(result, cancelFut) # isCancellation a good thing ?

method readChunkUnlocked(self: AsyncBuffer, cancelFut: Future[void]): Future[string] {.async.} =
    if self.readBuffer.isEmpty():
        return await self.stream.readUnlocked(self.readBufSize, cancelFut)
    else:
        return self.readBuffer.readChunk()

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

method readChunkUnlocked(self: AsyncIoDelayed, cancelFut: Future[void]): Future[string] {.async.} =
    await sleepAsync(self.delayMs)
    return await self.stream.readChunkUnlocked(cancelFut)

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

method readChunkUnlocked(self: AsyncTeeReader, cancelFut: Future[void]): Future[string] {.async.} =
    result = await self.reader.readChunkUnlocked(cancelFut)
    if result != "":
        discard await self.writer.write(result, cancelFut)

method writeUnlocked(self: AsyncBuffer, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    let dataLen = data.len()
    self.writeBuffer.write(data)
    if self.writeBuffer.len() >= self.writeBufSize:
        return await self.stream.writeUnlocked(self.writeBuffer.readAll(), cancelFut)
    else:
        return dataLen

method writeUnlocked(self: AsyncIoDelayed, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    await sleepAsync(self.delayMs)
    return await self.stream.writeUnlocked(data, cancelFut)

method writeUnlocked(self: AsyncStreamWriter, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    if self.closed or self.writerClosed[]:
        return 0
    self.hasData.trigger()
    self.buffer.write(data)
    return data.len()

method writeUnlocked(self: AsyncTeeWriter, data: string, cancelFut: Future[void]): Future[int] {.async.} =
    var allFuts = newSeqOfCap[Future[int]](self.writers.len())
    for w in self.writers:
        allFuts.add(w.writeUnlocked(data, cancelFut))
    for res in (await all(allFuts)):
        result += res

method writeUnlocked(self: AsyncVoid, data: string, cancelFut: Future[void]): Future[int] =
    result = newFuture[int]()
    if self.closed:
        result.complete(0)
    else:
        result.complete(data.len())
    