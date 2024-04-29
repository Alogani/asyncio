# Package

version       = "0.4.0"
author        = "alogani"
description   = "Async files and streams tools"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.2"
requires "asyncsync >= 0.2.0"


task reinstall, "Reinstalls this package":
    var path = "~/.nimble/pkgs2/" & projectName() & "-" & $version & "-*"
    exec("rm -rf " & path)
    exec("nimble install")
