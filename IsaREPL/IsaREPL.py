import msgpack as mp
import socket

REPLFail = type('REPLFail', (Exception,), {})

class Client:
    """
    A client for connecting Isabelle REPL
    """
    def __init__(self, addr, thy_qualifier="HOL"):
        """
        Create a client and connect to `addr`.

        If the script to be evaluated contains theory headers like
            `theory AAA imports A B C begin ... end`
        arguement `thy_qualifier` indicates the default session under which
        we should look for an import target (e.g. A) if it is not fully qualified,
        e.g. "List" instead of "HOL.List".
        """
        if not isinstance(thy_qualifier, str):
            raise ValueError("the argument thy_qualifier must be a string")

        def parse_address(address):
            host, port = address.split(':')
            return (host, int(port))

        self.sock  = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        host, port = parse_address(addr)
        self.sock.connect((host,port))
        self.cout  = self.sock.makefile('wb')
        self.cin   = self.sock.makefile('rb', buffering=0)
        self.unpack= mp.Unpacker(self.cin)

        mp.pack(thy_qualifier, self.cout)
        self.cout.flush()

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

    def eval(self, source):
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
        """
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        mp.pack(source, self.cout)
        self.cout.flush()
        return self.unpack.unpack()

    def __parse_control__(ret):
        if ret[1] is None:
            return ret[0]
        else:
            raise REPLFail(ret[1])

    def set_trace (self, trace):
        """
        By default, Isabelle REPL will collect all the output of every command,
        which causes the evaluation very slow.
        You can set the `trace` to false to disable the collection of the outputs,
        which speeds up the REPL a lot.
        """
        mp.pack ("\x05trace" if trace else "\x05notrace", self.cout)
        self.cout.flush()
        Client.__parse_control__(self.unpack.unpack())

    def lex (self, source):
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
        mp.pack ("\x05lex", self.cout)
        mp.pack (source, self.cout)
        self.cout.flush()
        return Client.__parse_control__(self.unpack.unpack())

    def boring_parse(data):
        """
        I am boring because I just convert the form of the data representation.
        This conversion just intends to explain the meaning of each data field,
        and convert the data into an easy-to-understand form.
        """
        if data[0] is None:
            outputs = None
        else: outputs = [{
            'command_name': output[0],
            'output': [{        # The same output in Isabelle's output panel.
                                # A list of messages.
                'type': msg[0], # The type is an integer, which can be
                                # 0 meaning NORMAL outputs printed by Isabelle/ML `writln`,
                                #       which denotes usual outputs;
                                # 1 meaning TRACING information printed by Isabelle/ML `tracing`,
                                #       which is trivial messages used usually for debugging;
                                # 2 meaning WARNING printed by Isabelle/ML `warning`,
                                #       which is some warning message.
                'content': msg[1] # A string, the output
                } for msg in output[1]],
            'output': output[2],
            'flags': [{                      # some Boolean flags.
                'is_toplevel': output[3][0], # whether the Isabelle state is outside any theory block
                                             # (the `theory XX imports AA begin ... end` block)
                'is_theory': output[3][1],   # whether the state is within a theory block and at the
                                             # toplevel of this block
                'is_proof' : output[3][2],   # whether the state is working on proving some goal
                'is_skipped_proof': output[3][3] # I dunno :P
                }],
            'level': output[4],     # The level of nesting context. It is some internal measure
                                    # and doesn't necessarily (but still roughly) reflect the
                                    # hiearchies of source code.
                                    # An integer.
            'state': output[5],     # the proof state as a string (the same content in the `State` pannel)
                                    # A string.
            'errors': output[6]     # any errors raised during evaluating this single command.
                                    # A list of strings.
            } for output in data[0]]
        return {
        'outputs': outputs, # A sequence of outputs each of which corresponds to one command.
        'error': data[1]    # Either None or a string,
                            # any error that interrtupts the evaluation process, causing the
                            # later commands not executed.

        }

    def silly_eval(self, source):
        ret = (self.eval(source))
        return Client.boring_parse(ret)

