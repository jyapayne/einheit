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

else:
  import posix
  type
    winsize = object
      ws_row: cushort
      ws_col: cushort
      ws_xpixel: cushort
      ws_ypixel: cushort

  let
    IOC_OUT = 0x40000000
    IOCPARM_MASK = 0x1fff

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
