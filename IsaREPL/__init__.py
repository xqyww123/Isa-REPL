from importlib.metadata import version

__version__ = version('IsaREPL')

from .IsaREPL import Client, REPLFail, Position, get_SYMBOLS, get_REVERSE_SYMBOLS
