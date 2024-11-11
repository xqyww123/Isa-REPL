import msgpack as mp
import socket

class Message_Type:
    """A fake enum"""
    NORMAL  = 1
    TRACING = 2
    WARNING = 3

def dbg(x):
    print(x)
    return x

class Client:
    """
    The client to connect Isabelle REPL
    """
    def __init__(self, addr, thy_qualifier="HOL"):
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
        We have to emphasize the `eval` method must accept complete commands ---
        It is strictly forbiddened to split a command into multiple parts individually
        sent to `eval`. You shouldn't split a command.
        Given this restriction, it can be helpful to split a script into a sequence of
        single commands. The `lex` method provides this funciton.
        """
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        mp.pack(source, self.cout)
        self.cout.flush()
        return self.unpack.unpack()

    def set_trace (self, enable):
        """
        By default, Isabelle REPL will collect all the output of every command.
        It causes the evaluation very slow.
        You can set the trace to false to disable the collection of the outputs,
        which speeds up the REPL a lot.
        """
        mp.pack ("\x05trace" if enable else "\x05notrace", self.cout)
        self.cout.flush()
        self.unpack.unpack()

    def lex (self, source):
        """
        We have to emphasize the `eval` method must accept complete commands ---
        It is strictly forbiddened to split a command into multiple parts individually
        sent to `eval`. You shouldn't split a command.
        Given this restriction, it can be helpful to split a script into a sequence of
        single commands. This `lex` provides this funciton.
        """
        if not isinstance(source, str):
            raise ValueError("the argument source must be a string")
        mp.pack ("\x05lex", self.cout)
        mp.pack (source, self.cout)
        self.cout.flush()
        return self.unpack.unpack()

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
            'message': [{
                'type': msg[0],
                'content': msg[1]
                } for msg in output[1]],
            'output': output[2],
            'flags': [{
                'is_toplevel': output[3][0], # if the Isabelle state is outside any theory block
                                             # (the `theory XX imports AA begin ... end` block)
                'is_theory': output[3][1],   # if the state is within a theory block and at the
                                             # toplevel of this block
                'is_proof' : output[3][2],   # if the state is working on proving some goal
                'is_skipped_proof': output[3][3] # I dunno :P
                }],
            'level': output[4],
            'state': output[5],     # the proof state as a string
            'errors': output[6]     # any errors raised during evaluating this single command.
            } for output in data[0]]
        return {
        'outputs': outputs, # every output corresponds to one command
        'error': data[1]
        }

    def silly_eval(self, source):
        ret = (self.eval(source))
        return Client.boring_parse(ret)

