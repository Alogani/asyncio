import ../exports/asynciobase {.all.}

import asyncsync, asyncsync/[event]

type AsyncTwoEnd* = ref object of AsyncIoBase
    ## Base type for objects where reader and writer connect to the same buffer
    ## Meaning that you can read with reader what was write to writer
    reader: AsyncIoBase
    writer: AsyncIoBase
    closeBehaviour: CloseBehaviour

proc init*(self: AsyncTwoEnd, reader, writer: AsyncIoBase, closeBehaviour: CloseBehaviour) =
    self.reader = reader
    self.writer = writer
    self.closeBehaviour = closeBehaviour
    self.init(reader.readLock, writer.writeLock)

proc reader*(self: AsyncTwoEnd): AsyncIoBase =
    self.reader

proc writer*(self: AsyncTwoEnd): AsyncIoBase =
    self.writer

method readAvailableUnlocked(self: AsyncTwoEnd, count: int, cancelFut: Future[
        void]): Future[string] =
    return self.reader.readAvailableUnlocked(count, cancelFut)

method readChunkUnlocked(self: AsyncTwoEnd, cancelFut: Future[void]): Future[string] =
    return self.reader.readChunkUnlocked(cancelFut)

method writeUnlocked(self: AsyncTwoEnd, data: string, cancelFut: Future[
        void]): Future[int] =
    return self.writer.writeUnlocked(data, cancelFut)

method close*(self: AsyncTwoEnd) =
    self.closed = true
    self.cancelled.trigger()
    if self.closeBehaviour in {CloseBoth, CloseReader}:
        self.reader.close()
    if self.closeBehaviour in {CloseBoth, CloseWriter}:
        self.writer.close()
    
