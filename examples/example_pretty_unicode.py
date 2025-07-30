#!/usr/bin/env python3
import IsaREPL

print("Pretty Unicode: \\<alpha> \\<Rightarrow> \\<beta>\\<^sub>1\\<^sup>2\\<^sup>x is ", IsaREPL.Client.pretty_unicode("\\<alpha> \\<Rightarrow> \\<beta>\\<^sub>1\\<^sup>2\\<^sup>x"))
print("ASCII of Unicode: A ⇒ B is ", IsaREPL.Client.ascii_of_unicode("A ⇒ B"))

print("Pretty Unicode: \\<forall> x. P x \\<Longrightarrow> \\<exists> y. Q y\\<^sub>1\\<^sup>2\\<^sup>x is ", IsaREPL.Client.pretty_unicode("\\<forall> x. P x \\<Longrightarrow> \\<exists> y. Q y\\<^sub>1\\<^sup>2\\<^sup>x"))

s = "[X\\<^sub>0, X\\<^sub>1, X\\<^sup>0, X\\<^sup>+, X\\<^sub>-, X\\<^sub>1\\<^sub>2]"
print(f"Pretty Unicode: {s} is ", IsaREPL.Client.pretty_unicode(s))
