from importlib.metadata import version

__version__ = version('IsaREPL')

from .IsaREPL import Client, REPLFail, Position, IsabellePosition
from Isabelle_RPC_Host.unicode import get_SYMBOLS, get_REVERSE_SYMBOLS
