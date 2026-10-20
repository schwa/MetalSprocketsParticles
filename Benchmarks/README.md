# Benchmarks

Performance baselines for the module refactor (#179).

- `baseline-presets.json`: every sample preset, whole frames (build, GPU, frame ms).
- `baseline-scenarios.json`: synthetic scenarios, 10K to 1M particles (simulate GPU, render GPU, CPU ms).

Recorded on an Apple M5 Max, release build, `--repeats 3`, at commit dc0ee23aefd2 (after #202; #214 re-recorded them because the first baselines had drifted).

Compare after each step:

```sh
xcb run particles-bench -c Release -- --presets --repeats 3 --compare $PWD/Benchmarks/baseline-presets.json
xcb run particles-bench -c Release -- --repeats 3 --compare $PWD/Benchmarks/baseline-scenarios.json
```

`--repeats` keeps the best median of each metric over several runs; with 1, frame times vary by up to 25% between identical runs. A row is a regression when it is slower by more than `--tolerance` percent (default 10) and by more than `--noise-floor` ms (default 0.05). The command exits with an error on any regression. Numbers depend on the machine; record a new baseline with `--save-baseline` on another machine, from a known commit.
