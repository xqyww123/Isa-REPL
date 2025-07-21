#!/usr/bin/env python3
import IsaREPL

print("Pretty Unicode: A \\<Rightarrow> B\\<^sub>1\\<^sup>2\\<^sup>x is ", IsaREPL.Client.pretty_unicode("A \\<Rightarrow> B\\<^sub>1\\<^sup>2\\<^sup>x"))
print("ASCII of Unicode: A ⇒ B is ", IsaREPL.Client.ascii_of_unicode("A ⇒ B"))
