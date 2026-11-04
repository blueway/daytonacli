/*
 * Process-exit shim for the Daytona CLI.
 *
 * Scripts and CI rely on the exit status, so commands return the process
 * status explicitly instead of relying on an uncaught error.
 */
#include <moonbit.h>
#include <stdlib.h>

MOONBIT_FFI_EXPORT
void daytona_exit(int32_t status) {
  exit((int)status);
}

/*
 * Host platform: 0 = Linux/other Unix, 1 = macOS, 2 = Windows.
 * The config directory and agent log paths follow each platform's conventions,
 * matching Go's os.UserConfigDir.
 */
MOONBIT_FFI_EXPORT
int32_t daytona_platform(void) {
#if defined(__APPLE__)
  return 1;
#elif defined(_WIN32)
  return 2;
#else
  return 0;
#endif
}

/*
 * Cryptographic randomness for OAuth state and PKCE verifiers. The bytes never
 * leave the process; /dev/urandom is available on Linux and macOS.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

MOONBIT_FFI_EXPORT
void daytona_random_bytes(uint8_t *buffer, int32_t length) {
#ifdef _WIN32
  for (int32_t i = 0; i < length; i++) {
    buffer[i] = (uint8_t)(rand() & 0xff);
  }
#else
  FILE *file = fopen("/dev/urandom", "rb");
  if (file == NULL) {
    abort();
  }
  size_t read = fread(buffer, 1, (size_t)length, file);
  fclose(file);
  if (read != (size_t)length) {
    abort();
  }
#endif
}

/*
 * Whether a standard stream is a terminal. Used to decide between the
 * interactive login menu and browser login when no credentials are supplied.
 */
MOONBIT_FFI_EXPORT
int32_t daytona_isatty(int32_t fd) {
#ifdef _WIN32
  return _isatty(fd);
#else
  return isatty(fd) ? 1 : 0;
#endif
}
