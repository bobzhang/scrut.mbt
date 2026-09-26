// Whether a standard stream is a terminal.
#ifdef _WIN32
#include <io.h>
int scrut_isatty(int fd) { return _isatty(fd) ? 1 : 0; }
#else
#include <unistd.h>
int scrut_isatty(int fd) { return isatty(fd) ? 1 : 0; }
#endif
