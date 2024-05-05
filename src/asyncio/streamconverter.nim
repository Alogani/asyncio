import std/streams
import asyncsync
import ./exports/asynciobase {.all.}

export streams


type
    StreamAsyncWrapper = ref object of StreamObj
        stream: AsyncIoBase


proc asclose(s: Stream)
proc asatEnd(s: Stream): bool
proc asreadLine(s: Stream; line: var string): bool
proc asreadData(s: Stream; buffer: pointer; bufLen: int): int
proc aswriteData(s: Stream; buffer: pointer; bufLen: int)
proc toStream*(stream: AsyncIoBase): StreamAsyncWrapper


proc asclose(s: Stream) =
    {.gcsafe, cast(tags: []).}:
        try:
            StreamAsyncWrapper(s).stream.close()
        except: discard

proc asatEnd(s: Stream): bool =
    false

proc asreadLine(s: Stream; line: var string): bool =
    try:
        {.gcsafe, cast(tags: []).}:
            line = StreamAsyncWrapper(s).stream.readLine().waitFor()
        if line.len > 0:
            result = true
    except: discard

proc asreadData(s: Stream; buffer: pointer; bufLen: int): int =
    var data: string
    try:
        {.gcsafe cast(tags: []).}:
            data = StreamAsyncWrapper(s).stream.read(buflen).waitFor()
    except: discard
    result = data.len()
    if result > 0:
        moveMem(buffer, addr(data[0]), result)

proc aswriteData(s: Stream; buffer: pointer; bufLen: int) =
    if buflen > 0:
        var data = newStringOfCap(bufLen)
        data.setLen(bufLen)
        copyMem(addr(data[0]), buffer, bufLen)
        {.gcsafe, cast(tags: []).}:
            try:
                discard StreamAsyncWrapper(s).stream.write(data).waitFor()
            except: discard


proc toStream*(stream: AsyncIoBase): StreamAsyncWrapper =
    StreamAsyncWrapper(stream: stream,
        closeImpl: asclose,
        atEndImpl: asatEnd,
        readLineImpl: asreadLine,
        readDataImpl: asreadData,
        writeDataImpl: aswriteData)