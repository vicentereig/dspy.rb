# MIPROv2 Gem Split – Packaging Notes

- New `dspy-miprov2.gemspec` ships `lib/dspy/teleprompt/mipro_v2.rb`, the Gaussian Process backend, and `lib/dspy/miprov2.rb`. Core `dspy` gem now excludes these files and no longer depends on Numo directly.
- Optimizer gem depends on `numo-narray-alt (~> 0.9)` and `numo-tiny_linalg (~> 0.4)`; installation requires OpenBLAS/LAPACK headers (brew `openblas`, apt `libopenblas-dev liblapacke-dev`, yum `openblas-devel lapack-devel`, apk `openblas-dev lapack-dev musl-dev gfortran`).
- CI follow-up: add a matrix leg that installs OpenBLAS before running bundler for `dspy-miprov2`, ensure specs for the optimizer run only when the gem is present, and publish both gems on release tags.
