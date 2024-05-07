import asyncsync
import ./exports/asynciobase {.all.}
import ./exports/asynciochilds

proc removeNils(streams: seq[AsyncIoBase]): seq[AsyncIoBase] =
    result = newSeqOfCap[AsyncIoBase](streams.len())
    for stream in streams:
        if stream != nil:
            result.add stream

proc buildReader*(chainReaders: seq[AsyncIoBase], captureStreams: seq[AsyncIoBase],
            closeEvent: Future[void] = nil, mustBeAFile = false): AsyncIoBase =
    ## Reading from return value is equivalent to reading from chainReaders argument
    ## If closeEvent is triggered, the built reader can reach EOF before chainReaders reach EOF.
    ## Providing closeEvent remove some optimizations to make it possible
    ## All input args and the return value should be closed manually by caller once done
    ## 
    ## Nil stream can be provided, they will be ignored
    let
        chainReaders = removeNils(chainReaders)
        captureStreams = removeNils(captureStreams)
    if chainReaders.len() == 0:
        return nil
    if chainReaders.len() == 1 and captureStreams.len() == 0 and closeEvent == nil:
        if (mustBeAFile and chainReaders[0] of AsyncFile) or not mustBeAFile:
            return chainReaders[0]
    var chainedInput = (if chainReaders.len() == 1:
        chainReaders[0]
    else:
        AsyncChainReader.new(@chainReaders))
    if mustBeAFile:
        var input: AsyncIoBase
        var output = AsyncPipe.new()
        if captureStreams.len() > 0:
            input = AsyncTeeReader.new(
                chainedInput,
                AsyncTeeWriter.new(@captureStreams)
            )
        else:
            input = chainedInput
        input.transfer(output.writer, closeEvent).addCallback(proc() =
            output.writer.close()
        )
        return output.reader
    var output = AsyncTeeReader.new(
        chainedInput,
        AsyncTeeWriter.new(@captureStreams),
        CancelOnly
    )
    if closeEvent != nil:
        closeEvent.addCallback(proc() =
            output.close()
        )
    return output

proc buildWriter*(writers: seq[AsyncIoBase], captureStreams: seq[AsyncIoBase],
            closeEvent: Future[void] = nil, mustBeAFile: bool): AsyncIoBase =
    ## writing to return value is equivalent to reading from writers argument
    ## If closeEvent is triggered, the built writer can reach EOF before writers reach EOF.
    ## All other documentation from buildReader applies
    let
        writers = removeNils(writers)
        captureStreams = removeNils(captureStreams)
    if writers.len() == 1 and captureStreams.len() == 0 and closeEvent == nil:
        if (mustBeAFile and writers[0] of AsyncFile) or not mustBeAFile:
            return writers[0]
    if mustBeAFile:
        var input: AsyncIoBase
        var output = AsyncPipe.new()
        input = AsyncTeeWriter.new(writers & captureStreams)
        output.transfer(input, closeEvent).addCallback(proc() =
            output.reader.close()
        )
        return output.writer
    else:
        var output = AsyncTeeWriter.new(
            writers & captureStreams,
            CancelOnly
        )
        closeEvent.addCallback(proc() =
            output.close()
        )
        return output