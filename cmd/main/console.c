#include <stdio.h>

// The Windows launcher tees stdout through a pipe. Prompts and progress must
// remain visible before stdin is supplied, not just when the process exits.
void repowayfinder_console_unbuffered(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
  setvbuf(stderr, NULL, _IONBF, 0);
}
