when defined(windows):
    raise newException(LibraryError)
else:
    include ./private/asyncpipe_posix