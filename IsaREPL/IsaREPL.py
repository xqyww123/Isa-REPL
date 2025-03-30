import msgpack as mp
import socket
import os
import signal
from collections import namedtuple
import re

REPLFail = type('REPLFail', (Exception,), {})


def _load_symbols(path, symbols={}, reverse_symbols={}):
    """
    Load Isabelle symbol file
    Return: (A dictionary from ASCII symbol to unicode symbol, and the reverse dictionary)
    """
    if not isinstance(path, str):
        raise ValueError("the argument path must be a string")
    if not os.path.exists(path):
        return symbols, reverse_symbols
    with open(path, 'r', encoding='utf-8') as file:
        for line in file:
            # Every line has a form like `\<odiv>            code: 0x002A38   font: PhiSymbols   group: operator   abbrev: (-:)`
            # Here we extract the `\<odiv>` part as a string and the `0x002A38` part as a character
            # Skip comments and empty lines
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            # Parse the line to extract symbol and code point
            parts = line.split()
            
            # Extract the symbol name (like \<odiv>)
            symbol = parts[0]
            
            # Find the code point (format can be either "code: 0x002A38" or "code:0x002A38")
            code_point = None
            for i, part in enumerate(parts[1:], 1):  # Start index at 1 since we're iterating from parts[1:]
                if part.startswith('code:'):
                    # Handle the case where there's no space after "code:"
                    if ':' in part and len(part) > 5:  # "code:" is 5 chars
                        code_point = part.split(':', 1)[1].strip()
                    # Otherwise, the hex value should be in the next part
                    elif i < len(parts) - 1:  # Check if there's a next element
                        code_point = parts[i + 1].strip()
                    break
            
            if symbol and code_point:
                try:
                    # Convert hex code point to unicode character
                    unicode_char = chr(int(code_point, 16))
                    # Add to dictionaries
                    symbols[symbol] = unicode_char
                    reverse_symbols[unicode_char] = symbol
                except ValueError:
                    # Skip if code point is invalid
                    continue
    return symbols, reverse_symbols

isabelle_home = os.popen("isabelle getenv -b ISABELLE_HOME").read().strip()
isabelle_home_user = os.popen("isabelle getenv -b ISABELLE_HOME_USER").read().strip()
SYMBOLS, REVERSE_SYMBOLS = {}, {}
for file in [f"{isabelle_home}/etc/symbols", f"{isabelle_home_user}/etc/symbols"]:
    SYMBOLS, REVERSE_SYMBOLS = _load_symbols(file, SYMBOLS, REVERSE_SYMBOLS)

class Position:
    def __init__(self, line, column, file):
        self.line = line
        self.column = column
        self.file = file

    def __str__(self):
        return f"{self.file}:{self.line}:{self.column}"

    def __repr__(self):
        return f"{self.file}:{self.line}:{self.column}"

    def __eq__(self, other):
        if not isinstance(other, Position):
            return False
        return (self.line == other.line and 
                self.column == other.column and 
                self.file == other.file)
    
    def __hash__(self):
        return hash((self.line, self.column, self.file))

    @staticmethod
    def from_s(position_str):
        parts = position_str.split(':')
        match parts:
            case [file, line, column, _]:
                return Position(int(line), int(column), file)
            case [file, line, column]:
                return Position(int(line), int(column), file)
            case [file, line]:
                return Position(int(line), 0, file)
            case [file]:
                return Position(0, 0, file)
            case _:
                raise ValueError("The string must be in the format: file:line:column")

def __unpack_position__(data):  
    line, offset, end_offset, tup3 = data
    label, file, id = tup3
    return Position(line, offset, file)

# There is a BUG! the position must be convretd from ML part.
def __repair_positions__(data):
    i = 0
    for pos, src in data:
        pos.column = i
        for _, c in enumerate(src):
            if c == '\n':
                i = 0
            else:
                i += 1

def is_list_of_strings(lst):
    if lst and isinstance(lst, list):
        return all(isinstance(elem, str) for elem in lst)
    else:
        return False


class Client:
    """
    A client for connecting Isabelle REPL
    """

    VERSION = '0.9.5'

    def __init__(self, addr, thy_qualifier, timeout=3600):
        """
        Create a client and connect it to `addr`.

        Arghument `thy_qualifier` is the session name used to parse short theory names,
        which will be qualified by this qualifier.
        Besides, any created theories during the evaluation will be qualified under
        `thy_qualifier`.

        For example, if you want to evaluate `$ISABELLE_HOME/src/HOL/List.thy`
        which imports `Lifting_Set` which is a short name while its full name
        is `HOL.Lifting_Set`.
        In this case, you must indicate `thy_qualifier = "HOL"`. Otherwise,
        the REPL cannot determine which import target do you mean.

        As another example, to evaluate
        `$AFP/thys/WebAssembly/Wasm_Printing/Wasm_Interpreter_Printing_Pure.thy`
        you should indicate `thy_qualifier = "WebAssembly"`.

        Basically, whenever you evaluate some existing file, the `thy_qualifier`
        should be the session name of that file.

        If you are unaware of the session name of a file, you could call
        `Client.session_name_of` to enquiry.

        You could also call `Client.set_thy_qualifier` to change this `thy_qualifier`
        after initialization.
        """
        if not isinstance(thy_qualifier, str):
            raise ValueError("the argument thy_qualifier must be a string")

        def parse_address(address):
            host, port = address.split(':')
            return (host, int(port))

        host, port = parse_address(addr)
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.cout = self.sock.makefile('wb')
        self.cin = self.sock.makefile('rb', buffering=0)
        self.unpack = mp.Unpacker(self.cin)

        mp.pack(Client.VERSION, self.cout)
        mp.pack(thy_qualifier, self.cout)
        self.cout.flush()
        self.pid = Client._parse_control_(self.unpack.unpack())

    def __enter__(self):
        return self
    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def close(self):
        if self.cout:
            self.cout.close()
            self.cout = None
        if self.cin:
            self.cin.close()
            self.cin = None
        if self.sock:
            self.sock.close()
            self.sock = None

    def eval(self, source, timeout=None, import_dir=None):
        """
        The `eval` method ONLY accepts **complete** commands ---
        It is strictly forbiddened to split a command into multiple fragments and
        individually send them to `eval` by multiple calls.

        Given this restriction, you may want to split a script into a command
        sequence (a sequence of code pieces, each of which corresponds to exactly
        one command). The `lex` method provides this funciton.

        The return of this method is a tuple
            (outputs, err_message)
        where `err_message` is either None or a string indicating any error that
        interrtupts the evaluation process (so the later commands are not executed).

        According to Isabelle's process behavior, the given `source` are split into
        a sequence of commands (this split is given by the `lex` method). Each
        command in the sequence is executed in order. Their outputs are stored in
        the `outputs` field, also in order.

        Method `silly_eval` interprets the meaning of each field in this output.

        Note, `outputs` can be None if you call `set_trace(false)` which disables
        the output printing.

        Timeout: the milliseconds to wait for the evaluation to finish.
        """
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        if timeout is not None and not isinstance(timeout, int):
            raise ValueError("the argument timeout must be an integer")
        if timeout is None and import_dir is None:
            mp.pack(source, self.cout)
        else:
            mp.pack("\x05eval", self.cout)
            mp.pack((source, timeout, import_dir), self.cout)
        self.cout.flush()
        return self.unpack.unpack()

    def _parse_control_(ret):
        if ret[1] is None:
            return ret[0]
        else:
            raise REPLFail(ret[1])

    def set_trace(self, trace):
        """
        By default, Isabelle REPL will collect all the output of every command,
        which causes the evaluation very slow.
        You can set the `trace` to false to disable the collection of the outputs,
        which speeds up the REPL a lot.
        """
        if not isinstance(trace, bool):
            raise ValueError("the argument trace must be a string")
        mp.pack("\x05trace" if trace else "\x05notrace", self.cout)
        self.cout.flush()
        Client._parse_control_(self.unpack.unpack())

    def set_register_thy(self, value):
        if not isinstance(value, bool):
            raise ValueError("the argument value must be a string")
        mp.pack("\x05register_thy" if value else "\x05no_register_thy", self.cout)
        self.cout.flush()
        Client._parse_control_(self.unpack.unpack())

    def lex(self, source):
        """
        This method splits the given `source` into a sequence of code pieces.
        Each piece is a string led by the keyword of a command, and no symbol
        occurs before this keyword).
        A piece contains exactly one command.
        Comments and blank spaces are usualy appended to the command before them.
        However, leading comments and spaces that occur before any command are discarded.
        """
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        mp.pack("\x05lex", self.cout)
        mp.pack(source, self.cout)
        self.cout.flush()
        ret = Client._parse_control_(self.unpack.unpack())
        ret = [(__unpack_position__(pos), src) for pos, src in ret]
        __repair_positions__(ret)
        return ret

    def fast_lex(self, source):
        """
        A faster but inaccurate version of `lex`.
        `lex` has to load all imports of the target source in order to use the correct
        set of Isar keywords (since libraries can define their own keywords).
        This faster version just use the predefined system keywords of Isar, so it
        doesn't need to load any imports but can fail to parse some user keywords.
        """
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        mp.pack("\x05lex'", self.cout)
        mp.pack(source, self.cout)
        self.cout.flush()
        ret = Client._parse_control_(self.unpack.unpack())
        ret = [(__unpack_position__(pos), src) for pos, src in ret]
        __repair_positions__(ret)
        return ret

    def plugin(self, name, ML, thy='Isa_REPL.Isa_REPL'):
        """
        Isa-REPL allows clients to insert user-specific plugins to collect data
        directly from Isabelle's internal representations about proof states, lemma
        context, lemma storage, and any other stuff of Isabelle.

        Argument `name` should uniquely identify the plugin. (We highly recommend the
            length of the `name` to be short. The name will be printed in the output
            of every command application, so a long name can consume too much bandwidth.)
        Arugment `ML` is the source code of the plugin.

        A plugin must be written in Isabelle/ML, a dialect of Standard Meta
        Language (cf., Isabelle's <implementation> manual, chapter 0 <Isabelle/ML>).
        Sadly, writing a plugin requires Isabelle development knowledge which is
        not well documented. Basically, you need to read Isabelle's source code, or
        pursue helps from some experts like me <xqyww123@gmail.com> :)
        You could find [some examples](https://github.com/xqyww123/Isa-REPL/tree/main/examples/example_plugin.py).

        A plugin must be a ML value having ML type
            Toplevel.state -> MessagePackBinIO.Pack.raw_packer option *
                              Toplevel.state option

        Type `Toplevel.state` represents the entire state of an Isabelle evaluation
        context. This type is defined in `$ISABELLE_HOME/src/Pure/Isar/toplevel.ML`.
        The same file also provides useful interfaces to allow you to for example,
        access the proof state by `Toplevel.proof_of`.
        ($ISABELLE_HOME is the base directory of your Isabelle installation,
         you could run `isabelle getenv -b ISABELLE_HOME` to obtain this location).

        Type `MessagePackBinIO.Pack.raw_packer` is defined in [our library](https://github.com/xqyww123/Isa-REPL/blob/main/contrib/mlmsgpack/mlmsgpack.sml?plain=1#L10).
        It is basically the result of applying a packer to a value that you want to export,
        e.g., `MessagePackBinIO.Pack.packBool True`.

        So, a plugin is a function accepting the evaluation state and returning optionally
        two values `(raw_packer, new_state)`.

        `raw_packer` embeds any data you want to export and the way how to encode it into
        messagepack format. The encoded data will be sent to this Python client, and unpacked
        automatically using the `msgpack` Python package.
        Set `raw_packer` to NONE if you have nothing to send to the Python client.

        `new_state` allows you to alter the evaluation state. Set `new_state` to NONE if you
        do not want to change the state.
        """
        if not isinstance(thy, str):
            raise ValueError("the argument thy must be a string")
        if not isinstance(name, str):
            raise ValueError("the argument name must be a string")
        if not isinstance(ML, str):
            raise ValueError("the argument ML must be a string")
        mp.pack("\x05plugin", self.cout)
        mp.pack(thy, self.cout)
        mp.pack(name, self.cout)
        mp.pack(ML, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def unplugin(self, name):
        """
        Remove an installed plugin.
        Argument `name` must be the name passed to the `plugin` method.
        This interface sliently does nothing if no plugin named `name` is installed.
        """
        if not isinstance(name, str):
            raise ValueError("the argument name must be a string")
        mp.pack("\x05unplugin", self.cout)
        mp.pack(name, self.cout)
        self.cout.flush()
        Client._parse_control_(self.unpack.unpack())

    def parse_output(output):
        return {
            'command_name': output[0],
            'output': [{  # The same output in Isabelle's output panel.
                # A list of messages.
                'type': msg[0],  # The type is an integer, which can be
                # 0 meaning NORMAL outputs printed by Isabelle/ML `writln`,
                #       which denotes usual outputs;
                # 1 meaning TRACING information printed by Isabelle/ML `tracing`,
                #       which is trivial messages used usually for debugging;
                # 2 meaning WARNING printed by Isabelle/ML `warning`,
                #       which is some warning message.
                'content': msg[1]  # A string, the output
            } for msg in output[1]],
            'latex': output[2],
            'flags': [{  # some Boolean flags.
                'is_toplevel': output[3][0],  # whether the Isabelle state is outside any theory block
                # (the `theory XX imports AA begin ... end` block)
                'is_theory': output[3][1],  # whether the state is within a theory block and at the
                # toplevel of this block
                'is_proof': output[3][2],  # whether the state is working on proving some goal
                'has_goal': output[3][3]  # whether the state has some goal to prove, or all goals are proven
            }],
            'level': output[4],  # The level of nesting context. It is some internal measure
            # and doesn't necessarily (but still roughly) reflect the
            # hiearchies of source code.
            # An integer.
            'state': output[5],  # the proof state as a string (the same content in the `State` pannel)
            # A string.
            'plugin_output': output[6],  # the output of plugins
            'errors': output[7]  # any errors raised during evaluating this single command.
            # A list of strings.
        }

    def boring_parse(data):
        """
        I am boring because I just convert the form of the data representation.
        This conversion just intends to explain the meaning of each data field,
        and convert the data into an easy-to-understand form.
        """
        if data[0] is None:
            outputs = None
        else:
            outputs = [Client.parse_output(output) for output in data[0]]
        return {
            'outputs': outputs,  # A sequence of outputs each of which corresponds to one command.
            'error': data[1]  # Either None or a string,
            # any error that interrtupts the evaluation process, causing the
            # later commands not executed.
            #
            # **No** error happens during the evaluation, **if and only if** this field is None.
            # However, if some error happens, this field may not provide all details.
            # Instead, the details can be given in `outputs['errors']`.
        }

    def silly_eval(self, source):
        ret = self.eval(source)
        return Client.boring_parse(ret)

    def record_state(self, name):
        """
        Record the current evaluation state so that later you could rollback to
        this state using name `name`.
        """
        if not isinstance(name, str):
            raise ValueError("the argument name must be a string")
        mp.pack("\x05record", self.cout)
        mp.pack(name, self.cout)
        self.cout.flush()
        Client._parse_control_(self.unpack.unpack())

    def clean_history(self):
        """
        Remove all recorded states.
        """
        mp.pack("\x05clean_history", self.cout)
        self.cout.flush()
        Client._parse_control_(self.unpack.unpack())

    def rollback(self, name):
        """
        Rollback to a recorded evaluation state named `name`.
        This method returns a description about the state just restored.
        This description can be parsed by `Client.parse_output`.
        However, the `command_name` fielld will be always an empty string,
        `output` be an empty list, and `latex` be NONE, because no command is executed.
        """
        if not isinstance(name, str):
            raise ValueError("the argument name must be a string")
        mp.pack("\x05rollback", self.cout)
        mp.pack(name, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def history(self):
        """
        Returns the names of all recorded states
        This method returns descriptions about all the recorded states.
        These descriptions can be parsed by `Client.parse_output`.
        However, the `command_name` fielld will be always an empty string,
        `output` be an empty list, and `latex` be NONE, because no command is executed.
        """
        mp.pack("\x05history", self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def silly_rollback(self, name):
        return Client.parse_output(self.rollback(name))

    def silly_history(self):
        return {k: Client.parse_output(v) for k, v in self.history().items()}

    def sexpr_term (self, term):
        """
        Parse a term and translate it into S-expression that reveals the full names
        of all overloaded notations.
        This interface can be called only under certain theory context, meaning you
        must have evaluated certain code like `theory THY imports Main begin` using
        the `eval` interface.
        """
        if not isinstance(term, str):
            raise ValueError("the argument term must be a string")
        mp.pack ("\x05sexpr_term", self.cout)
        mp.pack (term, self.cout)
        self.cout.flush()
        return Client.__parse_control__ (self.unpack.unpack())

    def fact (self, names):
        """
        Retreive a fact like a lemma, a theorem, or a corollary.
        The argument `names` has the same syntax with the argument of Isabelle command `thm`.
        Attributes are allowed, e.g., `HOL.simp_thms(1)[symmetric]`
        Names must be separated by space, e.g., `HOL.simp_thms conj_cong[symmetric] conjI`
        A list of pretty-printed string of the facts will be returned in the same order of the names.
        """
        if not isinstance(names, str):
            raise ValueError("the argument term must be a string")
        mp.pack ("\x05fact", self.cout)
        mp.pack (names, self.cout)
        self.cout.flush()
        return Client.__parse_control__ (self.unpack.unpack())

    def sexpr_fact (self, names):
        """
        Similar with `fact` but returns the S-expressions of the terms of the facts.
        """
        if not isinstance(names, str):
            raise ValueError("the argument term must be a string")
        mp.pack ("\x05sexpr_fact", self.cout)
        mp.pack (names, self.cout)
        self.cout.flush()
        return Client.__parse_control__ (self.unpack.unpack())

    def hammer (self, timeout):
        """
        Invoke Isabelle Sledgehammer within an indicated timeout (in seconds, and 0 means no timeout).
        Returns obtained tactic scripts if succeeds; or raises REPLFail on failure.
        The returned tactic `tac` is a string ready to be invoked by `apply (tac)`.
        Regardless if the hammer success, the REPL state will not be changed.
        You must manually evaluate `apply (tac)` to apply the obtained tactics.

        You could evaluate `declare [[REPL_sledgehammer_params = "ANY SLEDGEHAMMER PARAMETERS HERE"]]`
        to configure any Sledgehammer settings to be used in this interface.
        The configure takes the same syntax as indicated in the Sledgehammer reference (as attached
        to the Isabelle software package).
        Example: `declare [[REPL_sledgehammer_params = "provers = \\"cvc4 e spass vampire\\", minimize = false, max_proofs = 10"]]`
        Note: use *SINGLE* backslash in the code to be evaluated.

        This sledgehammer process is smart and will only return the first encoutered successful proofs.
        It pre-play every reported proof to test if it could be finish within a time limit. If not,
        it will not considered as a successful proof and be discarded; otherwise, the proof is returned
        immediately killing all other parallel attempts.
        This pre-play time limit is configurable by evaluating
        `delcare [[REPL_sledgehammer_preplay_timeout = <ANY SECONDS>]]`
        e.g, `delcare [[REPL_sledgehammer_preplay_timeout = 6]]`
        """
        if not isinstance(timeout, int):
            raise ValueError("the argument name must be an integer")
        mp.pack("\x05hammer", self.cout)
        mp.pack(timeout, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def context(self, s_expr):
        """
        Returns helpful contextual data including
            local facts, assumptions, bindings (made by `let` command), fixed term variables (and their types),
            fixed type variables (and their sorts), and goals.
        This retrival doesn't change the state of REPL.

        The formatter of S expression is given in ../library/REPL_serializer.ML:s_expr.
        """
        if not isinstance(s_expr, bool):
            raise ValueError("the argument s_expr must be a boolean")
        mp.pack("\x05context", self.cout)
        mp.pack(s_expr, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def parse_ctxt(raw):
        return {
            'local_facts': raw[0],
            'assumptions': raw[1],
            'bindings': raw[2],  # {name => (typ, term)}
            'fixed_terms': raw[3][0],
            'fixed_types': raw[3][1],
            'goals': raw[4]
        }

    def silly_context(self, s_expr):
        return Client.parse_ctxt(self.context(s_expr))

    def sexpr_term(self, term):
        """
        Parse a term and translate it into S-expression that reveals the full names
        of all overloaded notations.
        This interface can be called only under certain theory context, meaning you
        must have evaluated certain code like `theory THY imports Main begin` using
        the `eval` interface.
        """
        if not isinstance(term, str):
            raise ValueError("the argument term must be a string")
        mp.pack("\x05sexpr_term", self.cout)
        mp.pack(term, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def fact(self, names):
        """
        Retreive a fact like a lemma, a theorem, or a corollary.
        The argument `names` has the same syntax with the argument of Isabelle command `thm`.
        Attributes are allowed, e.g., `HOL.simp_thms(1)[symmetric]`
        Names must be separated by space, e.g., `HOL.simp_thms conj_cong[symmetric] conjI`
        A list of pretty-printed string of the facts will be returned in the same order of the names.
        """
        if not isinstance(names, str):
            raise ValueError("the argument `names` must be a string")
        mp.pack("\x05fact", self.cout)
        mp.pack(names, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def sexpr_fact(self, names):
        """
        Similar with `fact` but returns the S-expressions of the terms of the facts.
        """
        if not isinstance(names, str):
            raise ValueError("the argument `names` must be a string")
        mp.pack("\x05sexpr_fact", self.cout)
        mp.pack(names, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def set_thy_qualifier(self, thy_qualifier):
        """
        Change `thy_qualifier`.
        See `Client.__init__` for the explaination of `thy_qualifier`
        Returns None if success.
        """
        if not isinstance(thy_qualifier, str):
            raise ValueError("the argument `thy_qualifier` must be a string")
        mp.pack("\x05qualifier", self.cout)
        mp.pack(thy_qualifier, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def session_name_of(self, path):
        """
        Given a `path` to an Isabelle theory file, `session_name_of` returns
        the name of the session containing the theory file, or None if fails
        to figure this out.
        """
        if not isinstance(path, str):
            raise ValueError("the argument `path` must be a string")
        mp.pack("\x05session-of", self.cout)
        mp.pack(path, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def run_app(self, name):
        """
        Run user-defined applications.
        An application is an ML program registered through `REPL_Server.register_app`.
        It takes over the control of the in- and the out-socket stream, permitting the user
        to do anything he wants.
        """
        if not isinstance(name, str):
            raise ValueError("the argument `name` must be a string")
        mp.pack("\x05app", self.cout)
        mp.pack(name, self.cout)
        self.cout.flush()
        found = Client._parse_control_(self.unpack.unpack())
        if not found:
            raise KeyError
        return None

    def run_ML(self, thy, src):
        """
        Execute ML code in the global state of the Isabelle runtime.
        """
        if not isinstance(thy, str):
            raise ValueError("the argument `thy` must be a string")
        if not isinstance(src, str):
            raise ValueError("the argument `src` must be a string")
        mp.pack("\x05ML", self.cout)
        mp.pack((thy, src), self.cout)
        self.cout.flush()
        Client._parse_control_(self.unpack.unpack())
        return None

    def load_theory(self, targets, thy_qualifier=""):
        """
        Load theories. Short names can be used if the thy_qualifier is indicated.
        Otherwise, full names must be used.
        The target theories to be loaded must be registered to the Isabelle system
        through the `isabelle component -u` commands.
        The method returns the full names of the loaded theories.
        """
        if not isinstance(thy_qualifier, str):
            raise ValueError("the argument `thy_qualifier` must be a string")
        if not is_list_of_strings(targets):
            raise ValueError("the argument `targets` must be a list of strings")
        mp.pack("\x05load", self.cout)
        mp.pack((thy_qualifier, targets), self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def eval_file(self, path, line=~1, column=0, timeout=None):
        """
        Evaluate the file at the given path.
        This method has the same return as the `eval` method.
        Argument line and column indicate the REPL to evaluate all code
        until the first `column` characters at the `line`, meaning the REPL
        will stop at the position `line:column`.

        Timeout: the milliseconds to wait for the evaluation to finish.
        """
        if not isinstance(path, str):
            raise ValueError("the argument `path` must be a string")
        if not isinstance(line, int):
            raise ValueError("the argument `line` must be an int")
        if not isinstance(column, int):
            raise ValueError("the argument `column` must be an int")
        pos = None
        if line >= 0:
            pos = (line, column)
        mp.pack("\x05file", self.cout)
        mp.pack((path, pos, timeout), self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def add_lib(self, libs):
        """
        Add additional `libs` that will be loaded whenever evaluating a theory.
        :param libs:
        All names must be fully qualified, e.g. "HOL-Library.Sublist" instead of "Sublist"
        :return:
        None
        """
        if not is_list_of_strings(libs):
            raise ValueError("the argument `libs` must be a list of strings")
        mp.pack("\x05addlibs", self.cout)
        mp.pack(libs, self.cout)
        self.cout.flush()
        return Client._parse_control_(self.unpack.unpack())

    def num_processor (self):
        """
        :return: the number of processors available
        """
        mp.pack("\x05numcpu", self.cout)
        self.cout.flush()
        ret = Client._parse_control_(self.unpack.unpack())
        if ret <= 0:
            ret = 1
        return ret

    def kill(self):
        """
        Kill the entire server
        """
        os.kill(self.pid, signal.SIGKILL)

    @staticmethod
    def pretty_unicode(src):
        """
        Argument src: Any script that uses Isabelle's ASCII notation like `\\<Rightarrow>`
        Return: unicode version of `src`
        """
        # map every substring `s` in src to SYMBOLS[s] if s in SYMBOLS, otherwise s
        # Use a regular expression to find all potential Isabelle symbols
        pattern = r'\\<[^>]+>'
        
        # Function to replace each match with its Unicode equivalent if available
        def replace_symbol(match):
            symbol = match.group(0)
            return SYMBOLS.get(symbol, symbol)
        
        # Use re.sub to efficiently perform all replacements at once
        return re.sub(pattern, replace_symbol, src)

    @staticmethod
    def ascii_of_unicode(src):
        """
        Argument src: Any unicode string
        Return: Isabelle's ASCII version of `src`.
        This method is the reverse of `pretty_unicode`.
        """
        # map every character `c` in `src` to REVERSE_SYMBOLS[c] if c in REVERSE_SYMBOLS, otherwise c
        # Use str.translate with a translation table for maximum efficiency
        trans_table = str.maketrans(REVERSE_SYMBOLS)
        return src.translate(trans_table)
