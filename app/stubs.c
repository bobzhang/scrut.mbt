// Small platform helpers for the command line.
#include <stdint.h>
#include <string.h>
#include <time.h>
#include "moonbit.h"
#ifdef _WIN32
#include <io.h>
#include <windows.h>
#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#endif
#else
#include <unistd.h>
#endif

// Whether a standard stream is a terminal.
int scrut_isatty(int fd) {
#ifdef _WIN32
  return _isatty(fd) ? 1 : 0;
#else
  return isatty(fd) ? 1 : 0;
#endif
}

// Whether ANSI escape sequences work on a terminal stream: on Windows the
// console has to be switched to virtual terminal processing (as the
// `console` crate does).
int scrut_enable_ansi(int fd) {
#ifdef _WIN32
  HANDLE handle = GetStdHandle(fd == 2 ? STD_ERROR_HANDLE : STD_OUTPUT_HANDLE);
  DWORD mode = 0;
  if (handle == INVALID_HANDLE_VALUE || !GetConsoleMode(handle, &mode))
    return 0;
  if (mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING)
    return 1;
  return SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING) ? 1 : 0;
#else
  (void)fd;
  return 1;
#endif
}

// The local time as `YYYY-MM-DDTHH:MM:SS`, written to `out` (at least 20
// bytes); returns the length.
int scrut_local_timestamp(moonbit_bytes_t out) {
  time_t now = time(NULL);
  struct tm tm;
#ifdef _WIN32
  localtime_s(&tm, &now);
#else
  localtime_r(&now, &tm);
#endif
  return (int)strftime((char *)out, 20, "%Y-%m-%dT%H:%M:%S", &tm);
}
