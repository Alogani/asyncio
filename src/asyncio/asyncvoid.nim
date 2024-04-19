import ./exports/asynciobase {.all.}

type AsyncVoid* = ref object of AsyncIoBase
    ## Equivalent of a /dev/null

proc new*(T: type AsyncVoid): T
method writeUnlocked(self: AsyncVoid, data: string, cancelFut: Future[void]): Future[int]


proc new*(T: type AsyncVoid): T =
    result = T()
    result.init(readLock = Lock.new(), writeLock = Lock.new())

method writeUnlocked(self: AsyncVoid, data: string, cancelFut: Future[void]): Future[int] =
    result = newFuture[int]()
    result.complete(data.len())