# Timing-sensitive checks

A red quality gate stays red. A maintainer can rerun the smallest failing
suite with the same commit, toolchain and random seed to investigate. Keep
the original report and record both outcomes. A later pass on its own does
not identify the cause or qualify the failing run.

## Register

| Issue | Test surface | Current timing dependency |
| --- | --- | --- |
| #2967 | Large-document scale | Isolated benchmark. Median of paired samples with alternating order. The large case may cost less than 1.25 times two smaller cases. |
| #3088 | Warm privacy scan | Isolated benchmark. Seven measurements after JIT warm-up, with a median below 5 ms. |
| #3027 | Export image timeout and recovery | The timeout is the behaviour under test. Invalid input uses the short timeout. The successful recovery uses the normal production margin and waits for completion. |
| #3090 | Desktop microphone | Waits for a committed WAV frame. The deadline is a bound for missing progress. |
| #3147 | Privacy memoisation | Asserts cache misses and reuse in the ordinary suite. Wall-clock performance is checked by the separate #3088 benchmark. |
| #2818 | Fetch proxy TCP reset | Delivers the reset after receiving downstream response headers. Socket deadlines bound fixture failure. |
| #2829 | Web-deploy preflight | A 90-second subprocess deadline bounds the test harness on a loaded runner. Assertions check the output and filesystem, independently of elapsed time. |

Keep an elapsed-time performance assertion in the `benchmark` lane, which
runs with concurrency one. Prefer a completion signal in behavioural checks.
A timeout can bound a call while the result confirms what happened.

## Evidence sample

The package-suite incident in
[PR #3298](https://pawprint.vigilis.online/LibreKAT/Ocideck/pulls/3298)
records two red ordinary attempts and three later green ordinary controls for
the intermittent VM-service handshake. Four targeted attempts with the
workaround passed. Keep this incident distinct from an application assertion
failure. The observed two failures in five ordinary attempts describe the
incident sample alone.

For a suite-wide rate, retain the original JSON reports and classify each red
run as assertion failure, infrastructure failure, evidenced intermittent
failure, or undetermined. Record the commit and seed with any diagnostic
rerun. The Linux runner's original `build/test-report.json` records failures
and their tests. A report on its own cannot demonstrate intermittence, and
the historical artifacts do not provide paired controls for every red run.
