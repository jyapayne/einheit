when defined(windows):
  import winlean
  type
    SHORT = int16
    COORD = object
      X: SHORT
      Y: SHORT

    SMALL_RECT = object
      Left: SHORT
      Top: SHORT
      Right: SHORT
      Bottom: SHORT

    CONSOLE_SCREEN_BUFFER_INFO = object
      dwSize: COORD
      dwCursorPosition: COORD
      wAttributes: int16
      srWindow: SMALL_RECT
      dwMaximumWindowSize: COORD

  proc getConsoleScreenBufferInfo(hConsoleOutput: HANDLE,
    lpConsoleScreenBufferInfo: ptr CONSOLE_SCREEN_BUFFER_INFO): WINBOOL{.stdcall,
    dynlib: "kernel32", importc: "GetConsoleScreenBufferInfo".}

  proc getTermSize*(): (int, int) =
    let handle = getStdHandle(STD_OUTPUT_HANDLE)
    var scrbuf: CONSOLE_SCREEN_BUFFER_INFO
    let ret = getConsoleScreenBufferInfo(handle, addr(scrbuf))

    if ret == -1:
      return (-1, -1)

    let cols = scrbuf.srWindow.Right - scrbuf.srWindow.Left + 1
    let rows = scrbuf.srWindow.Bottom - scrbuf.srWindow.Top + 1

    return (rows.int, cols.int)

elif defined(ECMAScript) and defined(nodejs):
  type
    StreamObj {.importc.} = object
      columns: int
      rows: int

    ProcessObj {.importc.} = object
      stdout: ref StreamObj

  var
    process {.importc, nodecl.}: ref ProcessObj

  proc getTermSize*(): (int, int) =
    let t = process.stdout
    return (t.rows, t.columns)

else:
  import posix
  type
    winsize = object
      ws_row: cushort
      ws_col: cushort
      ws_xpixel: cushort
      ws_ypixel: cushort

  var
    TIOCGWINSZ{.importc: "TIOCGWINSZ", header: "<sys/ioctl.h>".}: uint

  proc ioctl*(f: int, device: uint, w: var winsize): int {.importc: "ioctl",
      header: "<sys/ioctl.h>", varargs, tags: [WriteIOEffect].}

  proc getTermSize*(): (int, int) =
    var w: winsize
    let ret = ioctl(STDOUT_FILENO, TIOCGWINSZ, addr(w))

    if ret == -1:
      return (-1, -1)

    return (w.ws_row.int, w.ws_col.int)
