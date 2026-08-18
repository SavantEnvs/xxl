/* mayhem/lsan_off.c -- build-time LeakSanitizer off-switch for the fuzz binary (SPEC SS6.2 item 15).
 *
 * XXL is an allocate-and-exit interpreter: the VM intentionally never frees its workspace, so
 * exit-time leak reports would drown the memory-safety bugs this target is fuzzed for.
 * -fsanitize=address always bundles LSan, so this TU (compiled with $SANITIZER_FLAGS and linked into
 * /mayhem/xxl by mayhem/build.sh) turns ONLY leak detection off; ASan's memory-corruption checks and
 * UBSan stay fully active. No runtime option is set here -- Mayhem owns the runtime ASan options. */
int __lsan_is_turned_off(void) { return 1; }
