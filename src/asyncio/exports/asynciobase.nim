import std/[asyncdispatch]
import asyncsync, asyncsync/[lock, event]


type
    AsyncIoBase* = ref object of RootRef
        ## Base type for all AsyncIo objects
        ## Define all methods and handle locks
        isClosed: bool
        readLock: Lock
        writeLock: Lock
        cancelled: Event

    CloseBehaviour* = enum
        ## Flag to set the closing behaviour of some high level objects containing multiple streams
        ## It always imply cancel and set its flag to "closed".
        ## You should know what you are doing or it could cause file descriptors leaks
        #
        # Concerns asynciochilds files
        CloseBoth, CloseReader, CloseWriter, CancelOnly

const
    ClearWaitMS = 5
    BufsizeLine = 80
    ChunkSize = 1024

#[
    Parent:
        - is responsible of Lock Handling
        - provide some default implementations
        - propose high level methods
    Children:
        - is responsible of everything else (Event handling)
        - can propose specific public procs
]#

{.push used.} # For children va import {.all.}
proc init(self: AsyncIoBase, readLock: Lock, writeLock: Lock) =
    ## All children must call it
    self.readLock = readLock
    self.writeLock = writeLock
    self.cancelled = Event.new()
proc cancelled(self: AsyncIoBase): Event =
    self.cancelled
proc `cancelled=`(self: AsyncIoBase, state: bool) =
    (if state: self.cancelled.trigger() else: self.cancelled.clear())
proc closed*(self: AsyncIoBase): bool =
    self.isClosed
proc `closed=`(self: AsyncIoBase, state: bool) =
    self.isClosed = state
proc readLock(self: AsyncIoBase): Lock =
    self.readLock
proc writeLock(self: AsyncIoBase): Lock =
    self.writeLock
{.pop.}

method close*(self: AsyncIoBase) {.gcsafe, base.} =
    discard

method readAvailableUnlocked(self: AsyncIoBase, count: int, cancelFut: Future[
        void]): Future[string] {.base.} =
    discard

method writeUnlocked(self: AsyncIoBase, data: string, cancelFut: Future[
        void]): Future[int] {.base.} =
    discard

method readUnlocked(self: AsyncIoBase, count: int, cancelFut: Future[
        void]): Future[string] {.async, base.} =
    while result.len() < count:
        let data = await self.readAvailableUnlocked(count - result.len(), cancelFut)
        if data == "":
            break
        result.add(data)

method readLineUnlocked(self: AsyncIoBase, keepNewLine = false,
        cancelFut: Future[void]): Future[string] {.async, base.} =
    # Default implementation
    # Unbuffered by default
    # Use '\n' to search for newline
    result = newStringOfCap(BufsizeLine)
    while true:
        let data = (await self.readAvailableUnlocked(1, cancelFut))
        if data == "":
            break
        if data == "\n": # TODO: not portable
            if keepNewLine:
                result.add("\n") # Most efficient to add str than char
            break
        result.add(data)

method readChunkUnlocked(self: AsyncIoBase, cancelFut: Future[void]): Future[
        string] {.base.} =
    self.readAvailableUnlocked(ChunkSize, cancelFut)

method readAllUnlocked(self: AsyncIoBase, cancelFut: Future[void]): Future[
        string] {.async, base.} =
    while true:
        let data = await self.readChunkUnlocked(cancelFut)
        if data == "":
            break
        result.add(data)

proc read*(self: AsyncIoBase, count: Natural, cancelFut: Future[
        void] = nil): Future[string] {.async.} =
    ## Await the data read len is count
    ##
    ## If cancelled was triggered, no attempt to read data is made and an empty string is returned.
    ## If cancelled is triggered during read, all available read data is returned (can be an empty string)
    withLock self.readLock, cancelFut:
        result = await self.readUnlocked(count, cancelFut)

proc readAvailable*(self: AsyncIoBase, count: Natural, cancelFut: Future[
        void] = nil): Future[string] {.async.} =
    ## Await at least one byte is available. So read can be from 1 byte to `count`
    ##
    ## If cancelled is triggered during read, an empty string is returned
    let cancelFut = any(self.cancelled, cancelFut)
    withLock self.readLock, cancelFut:
        result = await self.readAvailableUnlocked(count, cancelFut)

proc readChunk*(self: AsyncIoBase, cancelFut: Future[void] = nil): Future[
        string] {.async.} =
    ## Await at least one byte is available. Try to read a big chunk of data to optimize speed
    ##
    ## The exact size is implementation specific and can vary between objects
    let cancelFut = any(self.cancelled, cancelFut)
    withLock self.readLock, cancelFut:
        result = await self.readChunkUnlocked(cancelFut)

proc readLine*(self: AsyncIoBase, keepNewLine = false, cancelFut: Future[
        void] = nil): Future[string] {.async.} =
    ## Attempt to read up to a newline or to the end of stream
    ##
    ## newline can be kept if `keepNewLine` is set to true, which can be used to distinguish when end of stream is reached
    let cancelFut = any(self.cancelled, cancelFut)
    withLock self.readLock, cancelFut:
        result = await self.readLineUnlocked(keepNewLine, cancelFut)

proc readAll*(self: AsyncIoBase, cancelFut: Future[void] = nil): Future[
        string] {.async.} =
    let cancelFut = any(self.cancelled, cancelFut)
    withLock self.readLock, cancelFut:
        result = await self.readAllUnlocked(cancelFut)

proc write*(self: AsyncIoBase, data: string, cancelFut: Future[
        void] = nil): Future[int] {.async.} =
    ## Await write is available and write to it
    ##
    ## Number of bytes written is returned and can be inferior to `data.len()`
    let cancelFut = any(self.cancelled, cancelFut)
    withLock self.writeLock, cancelFut:
        result = await self.writeUnlocked(data, cancelFut)

proc writeDiscard*(self: AsyncIoBase, data: string, cancelFut: Future[
        void] = nil): Future[void] =
    ## Await write is available and write to it
    ##
    ## Number of bytes can be inferior to `data.len()`
    cast[Future[void]](self.write(data, cancelFut))


proc cancelAll*(self: AsyncIoBase) {.async.} =
    ## Kick out all pending readers and writers
    ##
    ## The consequence for readers and writers are the same as if they would have used `read(..., cancelFut)` or `write(..., cancelFut)`
    if self.cancelled.triggered and self.isClosed:
        return
    if (self.readlock != nil and self.readLock.locked) or
    (self.writeLock != nil and self.writeLock.locked):
        self.cancelled.trigger()
        if self.readLock != nil:
            await self.readLock.acquire()
            self.readLock.release()
        if self.writeLock != nil:
            self.writeLock.release()
            await self.writeLock.acquire()
        if not self.isClosed:
            self.cancelled.clear()

proc clear*(self: AsyncIoBase, cancelFut = sleepAsync(ClearWaitMS)) {.async.} =
    ## Execute cancelAll, then read all available data
    ## By default, use a minimal timer to know when data is fully read
    await self.cancelAll()
    while true:
        if await(self.readChunk(cancelFut)) == "":
            break

proc transfer*(src, dest: AsyncIoBase, cancelFut: Future[void] = nil,
        flushAndCloseAfter = false): Future[void] {.async.} =
    ## Transfer read from src immediatly to dest using readChunk
    ## Returns a future when completed
    ## If `flushAndCloseAfter` is set to true, src will be cleared then closed when transfer is over
    withLock src.readLock, cancelFut:
        while true:
            let data = await src.readChunkUnlocked(any(cancelFut,
                    dest.cancelled))
            if data == "":
                break
            let count = await dest.write(data, any(cancelFut, src.cancelled))
            if count == 0:
                break
    if flushAndCloseAfter:
        await src.clear()
        src.close()
