import ../exports/asynciobase {.all.}
import std/[posix]

type AsyncFile* = ref object of AsyncIoBase
    ## An AsyncFile implementation close to C methods
    fd*: cint
    osError*: cint
    pollable: bool
    unregistered: bool
    readListener: Listener
    writeListener: Listener
    

proc new*(T: type AsyncFile, fd: FileHandle): T
proc unregister*(self: AsyncFile)
proc isPollable(fd: cint): bool
proc readSelect(self: AsyncFile): Future[void]
proc writeSelect(self: AsyncFile): Future[void]
method readAvailableUnlocked(self: AsyncFile, count: int, cancelFut: Future[void]): Future[string]
method writeUnlocked(self: AsyncFile, data: string, cancelFut: Future[void]): Future[int]
method close*(self: AsyncFile)


proc new*(T: type AsyncFile, fd: FileHandle): T =
    result = T(fd: fd, readListener: Listener.new(), writeListener: Listener.new())
    if isPollable(fd):
        result.pollable = true
        AsyncFD(fd).register()
    else:
        result.pollable = false
        result.readListener.trigger()
        result.writeListener.trigger()
    result.init(Lock.new(), Lock.new())

proc unregister*(self: AsyncFile) =
    ## Clean everything except don't close the underlying file/fd
    if not self.unregistered:
        self.unregistered = true
        self.cancelled.trigger()
        if self.pollable:
            AsyncFD(self.fd).unregister()

proc isPollable(fd: cint): bool =
    ## EPOLL will throw error on regular file and /dev/null (warning: /dev/null not checked)
    ## Solution: no async on regular file
    var stat: Stat
    discard fstat(fd, stat)
    not S_ISREG(stat.st_mode)

method readAvailableUnlocked(self: AsyncFile, count: int, cancelFut: Future[void]): Future[string] {.async.} =
    if await checkWithCancel(self.readSelect(), any(cancelFut, self.cancelled)):
        result = newString(count)
        let bytesCount = posix.read(self.fd, addr(result[0]), count)
        if bytesCount == -1:
            self.osError = errno
            result.setLen(0)
        else:
            result.setLen(bytesCount)

method writeUnlocked(self: AsyncFile, data: string, cancelFut: Future[void]): Future[int]  {.async.} =
    if await checkWithCancel(self.writeSelect(), any(cancelFut, self.cancelled)):
        let bytesCount = posix.write(self.fd, addr(data[0]), data.len())
        if bytesCount == -1:
            self.osError = errno
            return 0
        else:
            result = bytesCount

method close*(self: AsyncFile) =
    if not self.isClosed():
        self.cancelled.trigger()
        self.isClosed = true
        self.unregister()
        discard self.fd.close()

proc readSelect(self: AsyncFile): Future[void] =
    result = self.readListener.wait()
    if not self.pollable or self.readListener.isListening():
        return
    if bool(self.cancelled):
        self.readListener.trigger()
        return
    self.readListener.clear()
    proc cb(fd: AsyncFD): bool {.closure gcsafe.} =
        self.readListener.trigger()
        true
    AsyncFD(self.fd).addRead(cb)

proc writeSelect(self: AsyncFile): Future[void] =
    result = self.writeListener.wait()
    if not self.pollable or self.writeListener.isListening():
        return
    if bool(self.cancelled):
        self.writeListener.trigger()
        return
    self.writeListener.clear()
    proc cb(fd: AsyncFD): bool {.closure gcsafe.}  =
        self.writeListener.trigger()
        true
    AsyncFD(self.fd).addWrite(cb)

#[
import terminal
proc transferWithTerminalControl*(input, inputDest, controlDest: AsyncIoBase, cancelFut: Future[void] = nil) {.async.} =
    ## input shall be unbuffered
    ## controlDest need to be able to process the terminal controls (typically stdout)
    ## Use rather a table as input to process also custom commands
    ## 
    ## Another solution is to spawn a true terminal which could be put on forground ?
    withLock input.readLock, cancelFut:
        while true:
            let data = await input.readUnlocked(1, any(cancelFut, inputDest.cancelled, controlDest.cancelled))
            if data == "":
                break
            ## Only send on newline char
            let count = await dest.write(data, any(cancelFut, src.cancelled))
            if count == 0:
                break
]#