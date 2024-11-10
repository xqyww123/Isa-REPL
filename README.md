### Example

This example is only tested on Linux, but it should also work on Mac OS.
This program is currently written for [Isabelle 2023](https://isabelle.in.tum.de/website-Isabelle2023/index.html), but Isabelle 2024 will be supported soon.

You must ensure `<Isaebelle_base_directory>/bin` is in your `$PATH` environment variable.

Startup server:
```
./repl_server.sh 127.0.0.1:6666 HOL
```

Run an example client
```
./example_client.py 127.0.0.1:6666
./eval_file.py 127.0.0.1:6666 $(isabelle getenv -b ISABELLE_HOME)/src/HOL/List.thy
```

