/* Baked ASan defaults for the fuzz binary: XXL is an allocate-and-exit interpreter (the VM
 * intentionally never frees its workspace), so exit-time leak reports would drown real bugs.
 * Mayhem owns ASAN_OPTIONS at run time, so bake the default here instead of the Mayhemfile. */
const char *__asan_default_options(void) { return "detect_leaks=0"; }
