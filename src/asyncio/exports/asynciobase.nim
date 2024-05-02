import std/[asyncdispatch]
import asyncsync, asyncsync/[lock, event]
export asyncsync

type
    AsyncIoBase* = ref object of RootRef
        isClosed: bool
        readLock: Lock
        writeLock: Lock
        cancelled: Event

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

proc read*(self: AsyncIoBase, count: Natural, cancelFut: Future[void] = nil): Future[string]
proc readAvailable*(self: AsyncIoBase, count: Natural, cancelFut: Future[void] = nil): Future[string]
proc readChunk*(self: AsyncIoBase, cancelFut: Future[void] = nil): Future[string]
proc readLine*(self: AsyncIoBase, keepNewLine = false, cancelFut: Future[void] = nil): Future[string]
proc readAll*(self: AsyncIoBase, cancelFut: Future[void] = nil): Future[string]
proc write*(self: AsyncIoBase, data: string, cancelFut: Future[void] = nil): Future[int]
proc writeDiscard*(self: AsyncIoBase, data: string, cancelFut: Future[void] = nil): Future[void]
proc transfer*(src, dest: AsyncIoBase, cancelFut: Future[void] = nil, flushAndCloseAfter = false): Future[void]
proc cancelAll*(self: AsyncIoBase)
proc clear*(self: AsyncIoBase): Future[void]
{.push base.} # Implementation details
method readUnlocked(self: AsyncIoBase, count: int, cancelFut: Future[void]): Future[string]
method readAvailableUnlocked(self: AsyncIoBase, count: int, cancelFut: Future[void]): Future[string] = discard
method readChunkUnlocked(self: AsyncIoBase, cancelFut: Future[void]): Future[string]
method readLineUnlocked(self: AsyncIoBase, keepNewLine = false, cancelFut: Future[void]): Future[string]
method readAllUnlocked(self: AsyncIoBase, cancelFut: Future[void]): Future[string]
method writeUnlocked(self: AsyncIoBase, data: string, cancelFut: Future[void]): Future[int] = discard
method close*(self: AsyncIoBase) {.gcsafe.} = discard
{.pop.}
{.push inline used.} # For children va import {.all.}
proc init(self: AsyncIoBase, readLock: Lock, writeLock: Lock)
proc isClosed*(self: AsyncIoBase): bool = self.isClosed
proc `isClosed=`(self: AsyncIoBase, state: bool) = self.isClosed = state
proc readLock(self: AsyncIoBase): Lock = self.readLock
proc writeLock(self: AsyncIoBase): Lock = self.writeLock
proc cancelled(self: AsyncIoBase): Event = self.cancelled
proc `cancelled=`(self: AsyncIoBase, state: bool) = (if state: self.cancelled.trigger() else: self.cancelled.clear())
{.pop.}


proc read*(self: AsyncIoBase, count: Natural, cancelFut: Future[void] = nil): Future[string] {.async.} =
    ## Await the data read len is count
    withLock self.readLock, cancelFut:
        result = await self.readUnlocked(count, cancelFut)

proc readAvailable*(self: AsyncIoBase, count: Natural, cancelFut: Future[void] = nil): Future[string] {.async.} =
    ## Await at least one byte is available
    withLock self.readLock, cancelFut:
        result = await self.readAvailableUnlocked(count, cancelFut)

proc readChunk*(self: AsyncIoBase, cancelFut: Future[void] = nil): Future[string] {.async.} =
    withLock self.readLock, cancelFut:
        result = await self.readChunkUnlocked(cancelFut)

proc readLine*(self: AsyncIoBase, keepNewLine = false, cancelFut: Future[void] = nil): Future[string] {.async.} =
    withLock self.readLock, cancelFut:
        result = await self.readLineUnlocked(keepNewLine, cancelFut)

proc readAll*(self: AsyncIoBase, cancelFut: Future[void] = nil): Future[string] {.async.} =
    withLock self.readLock, cancelFut:
        result = await self.readAllUnlocked(cancelFut)

proc write*(self: AsyncIoBase, data: string, cancelFut: Future[void] = nil): Future[int] {.async.} =
    withLock self.writeLock, any(self.cancelled, cancelFut): # Is it really useful ?
       result = await self.writeUnlocked(data, cancelFut)

proc writeDiscard*(self: AsyncIoBase, data: string, cancelFut: Future[void] = nil): Future[void] =
    cast[Future[void]](self.write(data, cancelFut))

proc transfer*(src, dest: AsyncIoBase, cancelFut: Future[void] = nil, flushAndCloseAfter = false): Future[void] {.async.} =
    ## Transfer read from src immediatly to dest
    ## Returns a future when completed
    ## src will be cleared and closed if closeAfter is set to true
    withLock src.readLock, cancelFut:
        while true:
            let data = await src.readChunkUnlocked(any(cancelFut, dest.cancelled))
            if data == "":
                break
            let count = await dest.write(data, any(cancelFut, src.cancelled))
            if count == 0:
                break
    if flushAndCloseAfter:
        await src.clear()
        src.close()

proc cancelAll*(self: AsyncIoBase) =
    if self.cancelled.triggered:
        # Definitly cancelled
        return
    if (self.readlock != nil and self.readLock.locked) or 
    (self.writeLock != nil and self.writeLock.locked):
        self.cancelled.trigger()
        if self.readLock != nil:
            waitFor self.readLock.acquire()
            self.readLock.release()
        if self.writeLock != nil:
            self.writeLock.release()
            waitFor self.writeLock.acquire()
        self.cancelled.clear()

proc clear*(self: AsyncIoBase) {.async.} =
    self.cancelAll()
    while true:
        if (await self.readChunk(sleepAsync(ClearWaitMS))) == "":
            break

proc init(self: AsyncIoBase, readLock: Lock, writeLock: Lock) =
    self.readLock = readLock
    self.writeLock = writeLock
    self.cancelled = Event.new()

method readUnlocked(self: AsyncIoBase, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    while result.len() < count:
        let data = await self.readAvailableUnlocked(count - result.len(), cancelFut)
        if data == "":
            break
        result.add(data)

method readLineUnlocked(self: AsyncIoBase, keepNewLine = false, cancelFut: Future[void]): Future[string] {.async.} =
    # Unbuffered, but any ssd will be blazingly faster than buffered
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

method readChunkUnlocked(self: AsyncIoBase, cancelFut: Future[void]): Future[string] =
    self.readAvailableUnlocked(ChunkSize, cancelFut)

method readAllUnlocked(self: AsyncIoBase, cancelFut: Future[void]): Future[string] {.async.} =
    while true:
        let data = await self.readChunkUnlocked(cancelFut)
        if data == "":
            break
        result.add(data)