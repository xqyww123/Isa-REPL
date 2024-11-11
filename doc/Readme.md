Isabelle REPL
====

Unofficial support for Isabelle's Read-Eval-Print-Loop.

- Python Client, easy for Machine Learning.
- Full support for all Isabelle commands
- Capability to trace proof state and output panel for each step of evaluation.
- Socket based remote communication
- Concurrency

## Installation

Ensuring `<ISABELLE-BASE-DIRECTORY>/bin` is in your `$PATH` environment
```
	isabelle components -u <THE-BASE-DIRECTORY-OF-OUR-PROGRAM>
pip install IsaREPL
```
## Start up the REPL server

```
# merely an example:
./repl_server.sh 127.0.0.1:6666 HOL ./tmp
```

Run `./repl_server.sh` to see the full explanation of the arguments and options.

## Example Clients

Every interface of our client is will documented (it is highly recommended to read our [source](./IsaREPL/IsaREPL.py)). Some examples are given in [the example folder](./examples).
```
# Run an example
./examples/example1.py
```

## Notes

### Concurrency

This REPL supports concurrent evaluation of multiple files. However, to ensure proper error tracking and result tracing, it disables Isabelle's concurrency between commands. While Isabelle typically executes `by` commands asynchronously (continuing to the next command before completion), this REPL enforces synchronous evaluation. Each command must complete before the next begins, allowing for accurate capture and reporting of any failures.

Sledgehammer (via our `auto_sledgehamemr` wrapper, see [example](./examples/example_sledgehammer.py)) is still concurrent.
### Communication Protocol

It is possible to implement a client in other languages. However, the document for the communication protocol is not provided and I refer you to read our source code, as it should be simple enough.
## Contribution

Feel free to open any GitHub issue if you have any feature requests.

I am not a professional python developer, so contribution is highly welcome to enrich the client's features.