#!/usr/bin/env python3
import IsaREPL

print("Pretty Unicode: A \\<Rightarrow> B is ", IsaREPL.Client.pretty_unicode("A \\<Rightarrow> B"))
print("ASCII of Unicode: A ⇒ B is ", IsaREPL.Client.ascii_of_unicode("A ⇒ B"))
