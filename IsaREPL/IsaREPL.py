import asyncio
import msgpack as mp
import os
import signal
from typing import Any, Callable
from enum import IntEnum
from importlib.metadata import version

from Isabelle_RPC_Host.position import IsabellePosition, Position

__version__ = version('IsaREPL')

REPLFail = type('REPLFail', (Exception,), {})

def is_list_of_strings(lst):
    if lst and isinstance(lst, list):
        return all(isinstance(elem, str) for elem in lst)
    else:
        return False


class MessageType(IntEnum):
    """
    Message type enumeration for Isabelle output messages.

    Values:
        NORMAL: 0 - Normal outputs printed by Isabelle/ML `writeln`
        TRACING: 1 - Tracing information printed by Isabelle/ML `tracing`
        WARNING: 2 - Warning printed by Isabelle/ML `warning`
    """
    NORMAL = 0
    TRACING = 1
    WARNING = 2


class CommandFlags:
    """
    Boolean flags indicating the state of the Isabelle session.

    Attributes:
        is_toplevel: Whether the Isabelle state is outside any theory block
        is_theory: Whether the state is within a theory block and at the toplevel of this block
        is_proof: Whether the state is working on proving some goal
        has_goal: Whether the state has some goal to prove, or all goals are proven
    """
    def __init__(self, is_toplevel: bool, is_theory: bool, is_proof: bool, has_goal: bool):
        self.is_toplevel = is_toplevel
        self.is_theory = is_theory
        self.is_proof = is_proof
        self.has_goal = has_goal

    def __repr__(self):
        return f"CommandFlags(is_toplevel={self.is_toplevel}, is_theory={self.is_theory}, is_proof={self.is_proof}, has_goal={self.has_goal})"


class CommandOutput:
    """
    Represents the output from evaluating a single Isabelle command.

    Attributes:
        command: The name of the command
        range: A tuple of (begin_pos, end_pos) indicating the range of the command,
               where each position is an IsabellePosition
        output: A list of (MessageType, str) tuples (the same output in Isabelle's output panel)
        latex: LaTeX output
        flags: Flags about the Isabelle state after executing the command
        level: The level of nesting context (an integer)
        state: The proof state as a string (the same content in the `State` panel)
        plugin_output: The output of plugins
        errors: A list of strings containing any errors raised during evaluating this command
    """
    def __init__(self, command: str, range: tuple, output: list, latex, flags: CommandFlags,
                 level: int, state: str, plugin_output, errors: list):
        self.command = command
        self.range = range
        self.output = output
        self.latex = latex
        self.flags = flags
        self.level = level
        self.state = state
        self.plugin_output = plugin_output
        self.errors = errors

    @classmethod
    def parse(cls, output):
        """
        Parse raw output data from Isabelle REPL into a CommandOutput instance.

        Args:
            output: Raw output data from Isabelle REPL (a list/tuple with specific structure)

        Returns:
            CommandOutput: A parsed CommandOutput instance
        """
        begin_pos, end_pos = output[8]
        # Parse output messages as (MessageType, str) tuples
        output_messages = [(MessageType(msg[0]), msg[1]) for msg in output[1]]
        # Parse flags
        flags = CommandFlags(
            is_toplevel=output[3][0],
            is_theory=output[3][1],
            is_proof=output[3][2],
            has_goal=output[3][3]
        )
        # Create and return CommandOutput instance
        return cls(
            command=output[0],
            range=(IsabellePosition.unpack(begin_pos), IsabellePosition.unpack(end_pos)),
            output=output_messages,
            latex=output[2],
            flags=flags,
            level=output[4],
            state=output[5],
            plugin_output=output[6],
            errors=output[7]
        )

    def __repr__(self):
        return (f"CommandOutput(command={repr(self.command)}, "
                f"range={self.range}, output={self.output}, latex={repr(self.latex)}, "
                f"flags={self.flags}, level={self.level}, state={repr(self.state)}, "
                f"plugin_output={repr(self.plugin_output)}, errors={self.errors})")


class Client:
    """
    A client for connecting Isabelle REPL
    """

    clients = {} # from client_id to Client instance

    def __init__(self, addr: str, thy_qualifier: str, timeout: int | None = 3600):
        """
        Initialize client attributes only. Use `Client.create()` to construct
        a connected client instance.
        """
        if not isinstance(thy_qualifier, str):
            raise ValueError("the argument thy_qualifier must be a string")

        self.addr = addr
        self.thy_qualifier = thy_qualifier
        self.timeout = timeout
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.unpack = mp.Unpacker()  # feed mode: no stream arg
        self.pid: int | None = None
        self.client_id: int | None = None

    @staticmethod
    def _parse_address(address):
        host, port = address.split(':')
        return (host, int(port))

    async def _feed_and_unpack(self) -> Any:
        """Read bytes from StreamReader, feed to Unpacker, return next msgpack object."""
        assert self.reader is not None, "Client not connected — use 'async with' or call __aenter__ first"
        while True:
            try:
                return self.unpack.unpack()
            except mp.OutOfData:
                data = await self.reader.read(65536)
                if not data:
                    raise ConnectionResetError("peer closed connection")
                self.unpack.feed(data)

    async def _write(self, *args):
        """Pack and send one or more msgpack values, then drain."""
        if self.writer is None or self.writer.is_closing():
            raise REPLFail(f"Client {self.client_id} is dead or closed")
        for a in args:
            self.writer.write(mp.packb(a))  # type: ignore[arg-type]
        await self.writer.drain()


    async def _read(self):
        return Client._parse_control_(await self._feed_and_unpack())

    def _chk_live(self):
        if self.writer is None or self.writer.is_closing():
            raise REPLFail(f"Client {self.client_id} is dead or closed")

    @classmethod
    async def test_server(cls, addr, timeout=60):
        host, port = addr.split(':')
        reader, writer = await asyncio.open_connection(host, port)
        try:
            unpack = mp.Unpacker()
            writer.write(mp.packb("heartbeat"))  # type: ignore[arg-type]
            await writer.drain()
            while True:
                try:
                    result = unpack.unpack()
                    break
                except mp.OutOfData:
                    data = await reader.read(65536)
                    if not data:
                        raise ConnectionResetError("peer closed connection")
                    unpack.feed(data)
            Client._parse_control_(result)
        finally:
            writer.close()
            await writer.wait_closed()


    async def __aenter__(self):
        host, port = self._parse_address(self.addr)
        self.reader, self.writer = await asyncio.open_connection(host, port)
        await self._write(__version__, self.thy_qualifier)
        (self.pid, self.client_id) = Client._parse_control_(await self._feed_and_unpack())
        Client.clients[self.client_id] = self
        return self
    async def __aexit__(self, exc_type, exc_value, traceback):
        self.close()

    @classmethod
    async def kill_client(cls, addr, client_id, timeout=60) -> bool:
        host, port = addr.split(':')
        reader, writer = await asyncio.open_connection(host, port)
        try:
            unpack = mp.Unpacker()
            writer.write(mp.packb("kill " + str(client_id)))  # type: ignore[arg-type]
            await writer.drain()
            while True:
                try:
                    result = unpack.unpack()
                    break
                except mp.OutOfData:
                    data = await reader.read(65536)
                    if not data:
                        raise ConnectionResetError("peer closed connection")
                    unpack.feed(data)
            return Client._parse_control_(result)
        finally:
            writer.close()
            await writer.wait_closed()


    def close(self):
        if self.writer is not None:
            try:
                self.writer.close()
            except:
                pass
        try:
            del Client.clients[self.client_id]
        except:
            pass

    @staticmethod
    def _parse_control_(ret):
        if ret[1] is None:
            return ret[0]
        else:
            raise REPLFail(ret[1])

    async def eval(self, source, timeout=None, cmd_timeout=None, import_dir=None, base_dir=None, configs=None):
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

        timeout: the milliseconds to wait for the evaluation to finish.
        cmd_timeout: the milliseconds to wait for every single command other than sledgehammer and auto_sledgehammer.
        """
        self._chk_live()
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        if timeout is not None and not isinstance(timeout, int):
            raise ValueError("the argument timeout must be an integer")
        if cmd_timeout is not None and not isinstance(cmd_timeout, int):
            raise ValueError("the argument cmd_timeout must be an integer")
        if configs is not None and not isinstance(configs, dict):
            raise ValueError("the argument configs must be a dictionary of strings")
        if configs and not all(isinstance(k, str) and isinstance(v, str) for k, v in configs.items()):
            configs = {k: str(v) for k, v in configs.items()}
        if import_dir is not None and not isinstance(import_dir, str):
            raise ValueError("the argument import_dir must be a string")
        if base_dir is not None and not isinstance(base_dir, str):
            raise ValueError("the argument base_dir must be a string")
        if import_dir is not None:
            import_dir = os.path.abspath(import_dir)
        if base_dir is not None:
            base_dir = os.path.abspath(base_dir)
        if timeout is None and import_dir is None and timeout is None and cmd_timeout is None and configs is None:
            await self._write(source)
        else:
            await self._write("\x05eval", (source, timeout, cmd_timeout, import_dir, base_dir, configs))
        ret = Client._parse_control_(await self._feed_and_unpack())
        if ret is None:
            return None
        else:
            return [CommandOutput.parse(output) for output in ret]

    async def set_trace(self, trace):
        """
        By default, Isabelle REPL will collect all the output of every command,
        which causes the evaluation very slow.
        You can set the `trace` to false to disable the collection of the outputs,
        which speeds up the REPL a lot.
        """
        self._chk_live()
        if not isinstance(trace, bool):
            raise ValueError("the argument trace must be a string")
        await self._write("\x05trace" if trace else "\x05notrace")
        Client._parse_control_(await self._feed_and_unpack())

    async def set_register_thy(self, value):
        self._chk_live()
        if not isinstance(value, bool):
            raise ValueError("the argument value must be a string")
        await self._write("\x05register_thy" if value else "\x05no_register_thy")
        Client._parse_control_(await self._feed_and_unpack())

    async def lex(self, source):
        """
        This method splits the given `source` into a sequence of code pieces.
        Each piece is a string led by the keyword of a command, and no symbol
        occurs before this keyword).
        A piece contains exactly one command.
        Comments and blank spaces are usualy appended to the command before them.
        However, leading comments and spaces that occur before any command are discarded.
        """
        self._chk_live()
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        await self._write("\x05lex", source)
        ret = await self._read()
        ret = [(Position.unpack(pos), src) for pos, src in ret]
        #__repair_positions__(ret)
        return ret

    async def lex_file(self, file):
        self._chk_live()
        if not isinstance(file, str):
            raise ValueError("the argument file must be a string")
        await self._write("\x05lex_file", os.path.abspath(file))
        ret = await self._read()
        ret = [(IsabellePosition.unpack(pos), src) for pos, src in ret]
        return ret

    async def fast_lex(self, source):
        """
        A faster but inaccurate version of `lex`.
        `lex` has to load all imports of the target source in order to use the correct
        set of Isar keywords (since libraries can define their own keywords).
        This faster version just use the predefined system keywords of Isar, so it
        doesn't need to load any imports but can fail to parse some user keywords.
        """
        self._chk_live()
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        await self._write("\x05lex'", source)
        ret = await self._read()
        ret = [(Position.unpack(pos), src) for pos, src in ret]
        #__repair_positions__(ret)
        return ret

    async def plugin(self, name, ML, thy='Isa_REPL.Isa_REPL'):
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
        self._chk_live()
        if not isinstance(thy, str):
            raise ValueError("the argument thy must be a string")
        if not isinstance(name, str):
            raise ValueError("the argument name must be a string")
        if not isinstance(ML, str):
            raise ValueError("the argument ML must be a string")
        await self._write("\x05plugin", thy, name, ML)
        return Client._parse_control_(await self._feed_and_unpack())

    async def unplugin(self, name):
        """
        Remove an installed plugin.
        Argument `name` must be the name passed to the `plugin` method.
        This interface sliently does nothing if no plugin named `name` is installed.
        """
        self._chk_live()
        if not isinstance(name, str):
            raise ValueError("the argument name must be a string")
        await self._write("\x05unplugin", name)
        Client._parse_control_(await self._feed_and_unpack())

    async def record_state(self, name):
        """
        Record the current evaluation state so that later you could rollback to
        this state using name `name`.
        """
        self._chk_live()
        if not isinstance(name, str):
            raise ValueError("the argument name must be a string")
        await self._write("\x05record", name)
        Client._parse_control_(await self._feed_and_unpack())

    async def clean_history(self):
        """
        Remove all recorded states.
        """
        self._chk_live()
        await self._write("\x05clean_history")
        Client._parse_control_(await self._feed_and_unpack())

    async def rollback(self, name):
        """
        Rollback to a recorded evaluation state named `name`.
        This method returns a description about the state just restored.
        However, the `command_name` fielld will be always an empty string,
        `output` be an empty list, and `latex` be NONE, because no command is executed.
        """
        self._chk_live()
        if not isinstance(name, str):
            raise ValueError("the argument name must be a string")
        await self._write("\x05rollback", name)
        ret = Client._parse_control_(await self._feed_and_unpack())
        return CommandOutput.parse(ret)

    async def history(self) -> dict[str, CommandOutput]:
        """
        Returns the names of all recorded states
        This method returns descriptions about all the recorded states.
        However, the `command_name` fielld will be always an empty string,
        `output` be an empty list, and `latex` be NONE, because no command is executed.
        """
        self._chk_live()
        await self._write("\x05history")
        ret = Client._parse_control_(await self._feed_and_unpack())
        return {k: CommandOutput.parse(v) for k, v in ret.items()}


    async def hammer (self, timeout):
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
        self._chk_live()
        if not isinstance(timeout, int):
            raise ValueError("the argument name must be an integer")
        await self._write("\x05hammer", timeout)
        return Client._parse_control_(await self._feed_and_unpack())

    async def context(self, pp='pretty'):
        """
        @return:
        A tuple of (
            local_facts: dict[str, thm],
            assumptions: [thm],
            binding: dict[str, (typ, term)], where the key is the name of the binding,
                note, a binding is something that appears like `?x` in Isabelle, e.g., let ?binding = 123.
            (fixed term variabls, fixed type variables): (dict[str, typ], dict[str, sort]),
            goals: [term]
        )
        where thm := str, in the encoding indicated by the pretty printer `pp`
            typ := str, in the encoding indicated by the pretty printer `pp`
            sort := [str]

        This retrival doesn't change the state of REPL.

        The formatter of S expression is given in ../library/REPL_serializer.ML:s_expr.
        """
        self._chk_live()
        if not isinstance(pp, str):
            raise ValueError("the argument pp must be a string")
        await self._write("\x05context", pp)
        return Client._parse_control_(await self._feed_and_unpack())

    @staticmethod
    def parse_ctxt(raw):
        return {
            'local_facts': raw[0],
            'assumptions': raw[1],
            'bindings': raw[2],  # {name => (typ, term)}
            'fixed_terms': raw[3][0],
            'fixed_types': raw[3][1],
            'goals': raw[4]
        }

    async def silly_context(self, s_expr):
        self._chk_live()
        return Client.parse_ctxt(await self.context(s_expr))

    async def sexpr_term(self, term):
        """
        Parse a term and translate it into S-expression that reveals the full names
        of all overloaded notations.
        This interface can be called only under certain theory context, meaning you
        must have evaluated certain code like `theory THY imports Main begin` using
        the `eval` interface.
        """
        self._chk_live()
        if not isinstance(term, str):
            raise ValueError("the argument term must be a string")
        await self._write("\x05sexpr_term", term)
        return Client._parse_control_(await self._feed_and_unpack())

    async def fact(self, names):
        """
        Retreive a fact like a lemma, a theorem, or a corollary.
        The argument `names` has the same syntax with the argument of Isabelle command `thm`.
        Attributes are allowed, e.g., `HOL.simp_thms(1)[symmetric]`
        Names must be separated by space, e.g., `HOL.simp_thms conj_cong[symmetric] conjI`
        A list of pretty-printed string of the facts will be returned in the same order of the names.
        """
        self._chk_live()
        if not isinstance(names, str):
            raise ValueError("the argument `names` must be a string")
        await self._write("\x05fact", names)
        return Client._parse_control_(await self._feed_and_unpack())

    async def sexpr_fact(self, names):
        """
        Similar with `fact` but returns the S-expressions of the terms of the facts.
        """
        self._chk_live()
        if not isinstance(names, str):
            raise ValueError("the argument `names` must be a string")
        await self._write("\x05sexpr_fact", names)
        return Client._parse_control_(await self._feed_and_unpack())

    async def set_thy_qualifier(self, thy_qualifier):
        """
        Change `thy_qualifier`.
        See `Client.__init__` for the explaination of `thy_qualifier`
        Returns None if success.
        """
        self._chk_live()
        if not isinstance(thy_qualifier, str):
            raise ValueError("the argument `thy_qualifier` must be a string")
        await self._write("\x05qualifier", thy_qualifier)
        return Client._parse_control_(await self._feed_and_unpack())

    async def session_name_of(self, path):
        """
        Given a `path` to an Isabelle theory file, `session_name_of` returns
        the name of the session containing the theory file, or None if fails
        to figure this out.
        """
        self._chk_live()
        if not isinstance(path, str):
            raise ValueError("the argument `path` must be a string")
        await self._write("\x05session-of", path)
        return Client._parse_control_(await self._feed_and_unpack())

    async def run_app(self, name):
        """
        Run user-defined applications.
        An application is an ML program registered through `REPL_Server.register_app`.
        It takes over the control of the in- and the out-socket stream, permitting the user
        to do anything he wants.
        """
        self._chk_live()
        if not isinstance(name, str):
            raise ValueError("the argument `name` must be a string")
        await self._write("\x05app", name)
        found = Client._parse_control_(await self._feed_and_unpack())
        if not found:
            raise KeyError
        return None

    async def run_ML(self, thy, src):
        """
        Execute ML code in the global state of the Isabelle runtime.
        """
        self._chk_live()
        if thy is not None and not isinstance(thy, str):
            raise ValueError("the argument `thy` must be a string")
        if not isinstance(src, str):
            raise ValueError("the argument `src` must be a string")
        await self._write("\x05ML", (thy, src))
        Client._parse_control_(await self._feed_and_unpack())
        return None

    async def load_theory(self, targets, thy_qualifier=""):
        """
        Load theories. Short names can be used if the thy_qualifier is indicated.
        Otherwise, full names must be used.
        The target theories to be loaded must be registered to the Isabelle system
        through the `isabelle component -u` commands.
        The method returns the full names of the loaded theories.
        """
        self._chk_live()
        if not isinstance(thy_qualifier, str):
            raise ValueError("the argument `thy_qualifier` must be a string")
        if not is_list_of_strings(targets):
            raise ValueError("the argument `targets` must be a list of strings")
        await self._write("\x05load", (thy_qualifier, targets))
        return Client._parse_control_(await self._feed_and_unpack())

    async def file(self, path : str, line : int = ~1, column : int = 0,
             timeout : int | None = None, attrs : list[str] = [],
             cache_position : bool = False, use_cache : bool = False):
        """
        Evaluate the file at the given path.
        This method only returns erros encountered during the evaluation.
        The evaluation may continue from a previously cached position if `use_cache` is True.
        The state at the position can be cached to be reused by later `file` calls if `cache_position` is True.

        Argument line and column indicate the REPL to evaluate all code
        until the first `column` characters at the `line`, meaning the REPL
        will stop at the position `line:column`.

        Timeout: the milliseconds to wait for the evaluation to finish.
        """
        self._chk_live()
        if not isinstance(path, str):
            raise ValueError("the argument `path` must be a string")
        if not isinstance(line, int):
            raise ValueError("the argument `line` must be an int")
        if not isinstance(column, int):
            raise ValueError("the argument `column` must be an int")
        if not isinstance(timeout, int | None):
            raise ValueError("the argument `timeout` must be an int or None")
        if not isinstance(cache_position, bool):
            raise ValueError("the argument `cache_position` must be a bool")
        if not isinstance(use_cache, bool):
            raise ValueError("the argument `use_cache` must be a bool")
        if not isinstance(attrs, list):
            raise ValueError("the argument `attrs` must be a list")
        pos = None
        if line >= 0:
            pos = (line, column)
        await self._write("\x05file", (path, pos, timeout, cache_position, use_cache, attrs))
        errs = Client._parse_control_(await self._feed_and_unpack())
        if errs:
            raise REPLFail('\n'.join(errs))
        return None

    async def clean_cache(self):
        """
        Clean the evaluation cache recorded by the `file` method.
        """
        self._chk_live()
        await self._write("\x05clean_cache")
        return Client._parse_control_(await self._feed_and_unpack())

    async def add_lib(self, libs):
        """
        Add additional `libs` that will be loaded whenever evaluating a theory.
        :param libs:
        All names must be fully qualified, e.g. "HOL-Library.Sublist" instead of "Sublist"
        :return:
        None
        """
        self._chk_live()
        if not is_list_of_strings(libs):
            raise ValueError("the argument `libs` must be a list of strings")
        await self._write("\x05addlibs", libs)
        return Client._parse_control_(await self._feed_and_unpack())

    async def num_processor (self):
        """
        :return: the number of processors available
        """
        self._chk_live()
        await self._write("\x05numcpu")
        ret = Client._parse_control_(await self._feed_and_unpack())
        if ret <= 0:
            ret = 1
        return ret

    async def set_cmd_timeout(self, timeout):
        """
        Set the timeout for commands other than sledgehammer and auto_sledgehammer.
        """
        self._chk_live()
        if not (isinstance(timeout, int) or timeout is None):
            raise ValueError("the argument `timeout` must be an int or None")
        await self._write("\x05cmd_timeout", timeout)
        return Client._parse_control_(await self._feed_and_unpack())

    def kill(self):
        """
        Kill the entire server
        """
        assert self.pid is not None, "Client not connected"
        os.kill(self.pid, signal.SIGKILL)

    async def path_of_theory(self, theory_name, master_directory):
        self._chk_live()
        if not isinstance(theory_name, str):
            raise ValueError("the argument `theory_name` must be a string")
        if not isinstance(master_directory, str):
            raise ValueError("the argument `master_directory` must be a string")
        await self._write("\x05path", (master_directory, theory_name))
        return Client._parse_control_(await self._feed_and_unpack())

    async def parse_thy_header(self, header_src):
        """
        Return: (fully_quantified_theory_name, theorys to import, keyword declarations)
        where fully_quantified_theory_name is a string,
              `theorys to import` is a list of strings, qualified or not as in the same shape of the given source,
        """
        self._chk_live()
        if not isinstance(header_src, str):
            raise ValueError("the argument `header_src` must be a string")
        lines = await self.fast_lex(header_src)
        theory_line = None
        for _, line in lines:
            if line.strip().startswith('theory'):
                theory_line = line.strip()
                break
        if not theory_line:
            raise ValueError("no `theory` declaration found in the given `header_src`")
        await self._write("\x05thy_header", theory_line)
        return Client._parse_control_(await self._feed_and_unpack())

    async def translate_position(self, src : str) -> Callable[[int | IsabellePosition], int | Position]:
        if not isinstance(src, str):
            raise ValueError("the argument `src` must be a string")
        await self._write("\x05symbpos", src)
        symbs = Client._parse_control_(await self._feed_and_unpack())

        # Implementation of column_of_pos functionality from SML
        # symbs is a list of strings (symbols), equivalent to Vector.map fst (Symbol_Pos.explode ...)
        # In SML, vectors are 1-indexed, but Python lists are 0-indexed
        ofs = 1
        line = 1
        colm = 1

        def calc(offset):
            nonlocal ofs, line, colm, symbs
            """Calculate line and column for a given offset (1-based)"""
            # offset corresponds to Position.offset_of pos
            # In Isabelle, symbol indices correspond to character offsets
            if offset < ofs:
                # Reset if we need to go backwards
                ofs = 1
                line = 1
                colm = 0

            # Walk through symbols until we reach the target offset
            # ofs is 1-based index, so we subtract 1 to access Python list
            while ofs < offset:
                idx = ofs - 1  # convert to 0-based index for Python list
                if idx < len(symbs):
                    s = symbs[idx]
                    if s == "\n":
                        line += 1
                        ofs += 1
                        colm = 1
                    else:
                        ofs += 1
                        colm += len(s)
                else:
                    break
            s = symbs[ofs - 1]
            if len(s) > 1:
                return colm - len(s) + 1
            else:
                return colm

        def translate(pos):
            if isinstance(pos, int):
                return calc(pos)
            elif isinstance(pos, IsabellePosition):
                column = calc(pos.raw_offset)
                return Position(pos.line, column, pos.file)
            else:
                raise TypeError("`pos` must be either an IsabellePosition or an integer")
        return translate


    async def premise_selection(self, mode, number : int, methods : list[str], params : dict[str, str] = {}, printer : str='pretty'):
        """
        Conduct the premise selection provided by Sledgehammer.
        @param number: the number of relevant premises to return
        @param methods: the methods to use for premise selection, any of ['mesh', 'mepo', 'mash']
        @param params: the parameters sent to Sledgehammer. Check Sledgehammer's user guide for details.
        @param printer: the printer to print the expressions of the retrived lemmas,
                        'pretty' for the system pretty printing, 'sexpr' for S-expression.
        @param mode: the mode of the premise selection, any of ['leading', 'final', 'each'].
            'leading': only select the lemmas relevant to the leading goal.
            'final' : select the lemmas relevant to the final goal(s).
                      Multiple final goals are connected by '&&' to be considered as a single goal.
            'each'  : select the lemmas relevant to each goal.
        @return:
            for mode = 'leading' or 'final':
                return a dictionary from the name of the retrived lemmas to their expressions.
            for mode = 'each':
                return a list of such dictionaries for each of the subgoal.
        """
        self._chk_live()
        if not isinstance(number, int):
            raise ValueError("the argument `number` must be an int")
        if not isinstance(methods, list):
            raise ValueError("the argument `methods` must be a list")
        if not isinstance(params, dict):
            raise ValueError("the argument `params` must be a dict")
        if not isinstance(printer, str):
            raise ValueError("the argument `printer` must be a string")
        if not isinstance(mode, str):
            raise ValueError("the argument `mode` must be a string")
        await self._write("\x05premise_selection", (number, methods, params, printer, mode))
        return Client._parse_control_(await self._feed_and_unpack())

    async def _health_of_clients(self):
        """
        Return a dictionary from the client_id to (live : bool, errors since last check : string list).
        You may use `Client.clients` to check the Client instance from the client_id.
        """
        self._chk_live()
        await self._write("\x05diagnosis")
        return dict(Client._parse_control_(await self._feed_and_unpack()))

    async def config(self, atrributes : list[str]):
        if not isinstance(atrributes, list):
            raise ValueError("the argument `atrributes` must be a list")
        if not all(isinstance(attr, str) for attr in atrributes):
            raise ValueError("every element in `atrributes` must be a string")
        await self._write("\x05config", atrributes)
        return await self._read()

    async def callback(self, name: str, arg=None):
        """
        Call a global callback registered in Isabelle_RPC.

        Global callbacks are registered on the Isabelle/ML side using
        Remote_Procedure_Calling.register_global_callback.

        Args:
            name: The name of the callback to invoke
            arg: The argument to pass to the callback (must match the callback's arg_schema)

        Returns:
            The callback's return value (unpacked from msgpack)
        """
        self._chk_live()
        if not isinstance(name, str):
            raise ValueError("the argument `name` must be a string")
        await self._write("\x05callback", name)
        # Phase 1: check if callback exists
        phase1 = await self._feed_and_unpack()
        if phase1[1] is not None:
            raise REPLFail(phase1[1])
        # Phase 2: send arg and read result
        await self._write(arg)
        ret = await self._feed_and_unpack()
        if ret[1] is not None:
            raise REPLFail(ret[1])
        return ret[0]

    _watchers = {}
    @classmethod
    async def install_watcher(cls, addr, handler, interval : int = 2, allow_multiple_watchers : bool = False, replace_existing : bool = True, verbose = False):
        """
        Install a watcher to monitor the health of each client regularly.

        handler: a funciton handling any abnormal status of client,
                 of type (client_id, (is_live : bool, errors : string list)) -> None
        interval: the interval in seconds to check the health of each client, default to 2 seconds.
        allow_multiple_watchers: By default, only one watcher is allowed. But you can allow multiple watchers
            by truning on this flag. Note, each error message can only be dispatched to one watcher of the multiple watchers randomly.
        """
        async def _watcher_loop(cancel_event: asyncio.Event):
            async with Client(addr, 'HOL') as client:
                while not cancel_event.is_set():
                    health_of_clients = await client._health_of_clients()
                    for cid, (is_live, errors) in health_of_clients.items():
                        if verbose or not is_live or errors:
                            handler(cid, (is_live, errors))
                    bads = None
                    for cid, cc in cls.clients.items():
                        if cid not in health_of_clients:
                            handler(cid, (False, []))
                            if bads is None:
                                bads = []
                            bads.append(cc)
                    if bads is not None:
                        for cc in bads:
                            cc.close()
                    try:
                        await asyncio.wait_for(cancel_event.wait(), timeout=interval)
                        break  # event was set, stop the loop
                    except asyncio.TimeoutError:
                        pass  # timeout expired, continue loop

        if addr in cls._watchers:
            watchers = cls._watchers[addr]
        else:
            watchers = []
            cls._watchers[addr] = watchers
        if replace_existing:
            for _, cancel_event in watchers:
                cancel_event.set()
            watchers.clear()
        if watchers and not allow_multiple_watchers:
            raise ValueError("Only one watcher is allowed")
        cancel_event = asyncio.Event()
        task = asyncio.create_task(_watcher_loop(cancel_event))
        watchers.append((task, cancel_event))
