# Swish Concurrency Engine

The Swish Concurrency Engine is a framework used to write fault-tolerant programs with message-passing concurrency. It uses the Chez Scheme programming language and embeds concepts from the Erlang programming language. Swish also provides a web server.  A Swish program is a Microsoft Windows console application that can also be run as a service.

# Build system requirements

- Microsoft Windows 10
- Cygwin with bash, git, graphviz, grep, perl, texlive, etc.
- Microsoft Visual Studio 2017
- Microsoft Windows Software Development Kit - Windows 10.0.16299
- NSIS 2.46

## Target system requirements

- Microsoft Windows Vista or later. A 64-bit version is required to run code compiled for 64-bit Windows.
- Administrator rights for the installation

## Make the documentation

1. `cd doc`
1. `make`

`doc/swish.pdf` is the design book.

## Run the tests

1. `cd src`
1. `./run-osi 32`
1. `./run-mats 32`
1. `./run-osi 64`
1. `./run-mats 64`

## Change the name of the executable, the product name, or the version number

1. `cd src`
1. Edit `software-info.ss`
1. `make`

## Run the read-eval-print loop (repl)

1. `cd src`
1. `./scheme32 repl.ss`

## Make the 32-bit install

1. `cd src`
1. `make install`

The install placed is in the `bin` folder. Its name depends on the `software-product-name` defined in `src/software-info.ss`.
