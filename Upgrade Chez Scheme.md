# Upgrade Chez Scheme

This outline uses the example of upgrading [Chez Scheme](https://cisco.github.io/ChezScheme/) from version 9.5 to version 9.5.1.

1. Update the `ChezScheme` git submodule.

1. Read the Chez Scheme Version 9.5.1 release notes. Assess the new features, changed features, and bug fixes.

1. Rename `csv95mt.lib` to `csv951mt.lib` in `build-chez` and `src/swish/stdafx.cpp`.

1. Run `build-chez`.

1. Compare `ChezScheme/c/main.c` against `src/swish/main.cpp`, and integrate the changes.

1. Run `git grep -l 9[.]5` from the root of the repository to find all references to 9.5. Update them.

1. Build and test the system.
