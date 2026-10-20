# Benchmarks

Performance baselines for the module refactor (#179). Recorded on the code before the refactor, release build.

- `baseline-presets.json`: every sample preset, whole frames (build, GPU, frame ms).
- `baseline-scenarios.json`: synthetic scenarios, 10K to 1M particles (simulate GPU, render GPU, CPU ms).

Compare after each step:

```sh
xcb run particles-bench -c Release -- --presets --compare $PWD/Benchmarks/baseline-presets.json
xcb run particles-bench -c Release -- --compare $PWD/Benchmarks/baseline-scenarios.json
```

A row is a regression when it is slower by more than `--tolerance` percent (default 10) and by more than `--noise-floor` ms (default 0.05). The command exits with an error on any regression. Numbers depend on the machine; record a new baseline with `--save-baseline` on a new machine, from the pre-refactor code.
