/* mayhem/watchdog_main.c -- hard process-level wall-clock bound for the XXL interpreter.
 *
 * XXL is a tree-walking interpreter over untrusted source (parse+eval, driven by
 * mayhem/build.sh's fuzz binary as a raw file-input, process-per-input target -- see
 * mayhem/Mayhemfile). The language's own iteration verbs (`exhaust`/`recurse`) self-limit
 * to an internal ~2048-step stack check (confirmed: `0 exhaust {+1}` returns an `exhausted`
 * exception rather than looping), but that is a property of those two verbs, not of the
 * language: an ordinary self-recursive lambda is NOT bounded at all. Verified empirically
 * with a hand-written infinite-loop program:
 *
 *     0 {self as 'f; x f}
 *
 * This spins forever, confirmed via gdb attach to be actively looping in
 * applyexpr()/xln()/xalloc() (unbounded allocation on every call, matching the "allocate
 * and exit" workspace design noted in mayhem/asan_default_options.c) -- it never blocks,
 * never returns, and RSS grows without bound. Since the target is a raw process-per-input
 * executable (no libfuzzer:, no in-process harness), a single such input would otherwise
 * hang that one Mayhem execution forever and stall the whole campaign (a hang, unlike a
 * crash, cannot be recovered from mid-run -- see docs/netnew-worker-prompt.md SS6b). So a
 * hard wall-clock cap is installed BEFORE any XXL code runs at all, independent of what the
 * interpreter itself does or catches.
 *
 * Renaming trick (keeps this purely additive -- upstream's xxl.c is never edited):
 * mayhem/build.sh compiles the fuzz build's xxl.c with `-Dmain=xxl_upstream_main`, turning
 * upstream's real `int main(...)` into an ordinary function this file wraps. This flag is
 * applied ONLY to the sanitized fuzz build, never to the clean upstream-selftest build
 * (mayhem/test.sh's oracle binary), so the oracle keeps running upstream's real,
 * unmodified main() and stays an honest, unwatchdogged functional test.
 */
#include <signal.h>
#include <stdlib.h>
#include <sys/time.h>
#include <unistd.h>

extern int xxl_upstream_main(int argc, char *argv[]);

/* ~1.5s: comfortably above every seed's real runtime (all under 20ms, empirically timed),
 * comfortably below anything that would stall a fuzzing campaign on one hung input. */
#define MAYHEM_WATCHDOG_USEC 1500000

static void mayhem_alarm_handler(int sig) {
    (void)sig;
    /* _exit(), not exit(): async-signal-safe, skips atexit/stdio flush -- we are
     * abandoning a stuck process, not shutting one down cleanly. 124 mirrors the
     * conventional coreutils `timeout` hang exit code so it reads unambiguously in logs. */
    _exit(124);
}

int main(int argc, char *argv[]) {
    struct sigaction sa;
    sa.sa_handler = mayhem_alarm_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGALRM, &sa, NULL);

    struct itimerval it;
    it.it_interval.tv_sec = 0;
    it.it_interval.tv_usec = 0;
    it.it_value.tv_sec  = MAYHEM_WATCHDOG_USEC / 1000000;
    it.it_value.tv_usec = MAYHEM_WATCHDOG_USEC % 1000000;
    setitimer(ITIMER_REAL, &it, NULL);

    return xxl_upstream_main(argc, argv);
}
