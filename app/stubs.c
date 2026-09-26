// Small platform helpers for the command line.
#include <stdint.h>
#include <string.h>
#include <time.h>
#include "moonbit.h"
#ifdef _WIN32
#include <io.h>
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
