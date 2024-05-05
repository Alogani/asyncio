import ../exports/asynciobase {.all.}
import ./asynctwoend

import asyncsync, asyncsync/[event, lock, osevents]
import std/[posix, os]

type
    AsyncFile* = ref object of AsyncIoBase
        ## An AsyncFile implementation close to C methods
        fd*: cint
        osError*: cint
        pollable: bool
        unregistered: bool
        readEvent: ReadEvent
        writeEvent: WriteEvent
    
    AsyncPipe* = ref object of AsyncTwoEnd


proc new*(T: type AsyncFile, fd: FileHandle, direction = fmReadWrite): T
let
    stdinAsync* = AsyncFile.new(STDIN_FILENO)
    stdoutAsync* = AsyncFile.new(STDOUT_FILENO)
    stderrAsync* = AsyncFile.new(STDERR_FILENO)

proc isPollable(fd: cint): bool =
    ## EPOLL will throw error on regular file and /dev/null (warning: /dev/null not checked)
    ## Solution: no async on regular file
    var stat: Stat
    discard fstat(fd, stat)
    not S_ISREG(stat.st_mode)

proc isReader(mode: FileMode): bool =
    mode in [fmRead, fmReadWrite, fmReadWriteExisting]

proc isWriter(mode: FileMode): bool =
    mode in [fmWrite, fmReadWrite, fmReadWriteExisting, fmAppend]

proc new*(T: type AsyncFile, fd: FileHandle, direction = fmReadWrite): T =
    if isPollable(fd):
        result = T(
            fd: fd,
            pollable: true,
            readEvent: if direction.isReader(): ReadEvent.new(fd) else: nil,
            writeEvent: if direction.isWriter(): WriteEvent.new(fd) else: nil,
        )
        AsyncFD(fd).register()
    else:
        result = T(
            fd: fd,
            pollable: false,
        )
    result.init(
        # Read/Write locks
        if direction.isReader(): Lock.new() else: nil,
        if direction.isWriter(): Lock.new() else: nil,
    )

proc new*(T: type AsyncFile, file: File, direction = fmReadWrite): T =
    T.new(file.getOsFileHandle(), direction)

proc new*(T: type AsyncFile, path: string, mode = fmRead): T =
    T.new(open(path, mode), mode)

proc new*(T: type AsyncPipe): T =
    var pipesArr: array[2, cint]
    if pipe(pipesArr) != 0:
        raiseOSError(osLastError())
    result = T()
    result.init(
        reader = AsyncFile.new(pipesArr[0], fmRead),
        writer = AsyncFile.new(pipesArr[1], fmWrite)
    )

proc readSelect(self: AsyncFile): Future[void] =
    if not self.pollable:
        let fut = newFuture[void]()
        fut.complete()
        return fut
    return self.readEvent.getFuture()

proc reader*(self: AsyncPipe): Asyncfile =
    (procCall self.AsyncTwoEnd.reader()).Asyncfile


proc writeSelect(self: AsyncFile): Future[void] =
    if not self.pollable:
        let fut = newFuture[void]()
        fut.complete()
        return fut
    return self.writeEvent.getFuture()

proc unregister*(self: AsyncFile) =
    ## This is equivalent to a soft close
    ## 
    ## This means, it will considered as closed when trying to read/write to it, but the underlying file descriptor will still be open
    if not self.unregistered:
        self.unregistered = true
        self.cancelled.trigger()
        if self.pollable:
            AsyncFD(self.fd).unregister()

method close(self: AsyncFile) =
    if not self.closed():
        self.cancelled.trigger()
        self.closed = true
        self.unregister()
        discard self.fd.close()

method readAvailableUnlocked(self: AsyncFile, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    if await self.readSelect().wait(any(cancelFut, self.cancelled)):
        result = newString(count)
        let bytesCount = posix.read(self.fd, addr(result[0]), count)
        if bytesCount == -1:
            self.osError = errno
            result.setLen(0)
        else:
            result.setLen(bytesCount)

method writeUnlocked(self: AsyncFile, data: string, cancelFut: Future[void]): Future[int]  {.async.} =
    if await self.writeSelect().wait(any(cancelFut, self.cancelled)):
        let bytesCount = posix.write(self.fd, addr(data[0]), data.len())
        if bytesCount == -1:
            self.osError = errno
            return 0
        else:
            result = bytesCount

proc writer*(self: AsyncPipe): AsyncFile =
    (procCall self.AsyncTwoEnd.writer()).Asyncfile