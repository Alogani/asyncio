import std/unittest
import asyncio, asyncio/[asyncstream]

import ./pipechecks

pipeTester("AsyncStream", AsyncStream)