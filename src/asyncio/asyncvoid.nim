import ./exports/asynciobase {.all.}

import asyncsync, asyncsync/[lock]

type AsyncVoid* = ref object of AsyncIoBase
    ## AsyncObject that does nothing and can only be written to
    ## Equivalent of a /dev/null, write to it will do nothing

proc new*(T: type AsyncVoid): T
method writeUnlocked(self: AsyncVoid, data: string, cancelFut: Future[void]): Future[int]


proc new*(T: type AsyncVoid): T =
    result = T()
    result.init(readLock = Lock.new(), writeLock = Lock.new())

method writeUnlocked(self: AsyncVoid, data: string, cancelFut: Future[void]): Future[int] =
    result = newFuture[int]()
    if self.isClosed:
        result.complete(0)
    else:
        result.complete(data.len())

method close*(self: AsyncVoid) =
    self.isClosed = true