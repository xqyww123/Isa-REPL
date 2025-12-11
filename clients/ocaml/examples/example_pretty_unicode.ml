(** Example: Pretty Unicode conversion

    This example demonstrates Unicode ↔ ASCII conversion.
*)

open Isa_repl

let () =
  Printf.printf "Pretty Unicode: \\<alpha> \\<Rightarrow> \\<beta>\\<^sub>1\\<^sup>2\\<^sup>x is %s\n"
    (unicode_of_ascii "\\<alpha> \\<Rightarrow> \\<beta>\\<^sub>1\\<^sup>2\\<^sup>x");

  Printf.printf "ASCII of Unicode: A ⇒ B is %s\n"
    (ascii_of_unicode "A ⇒ B");

  Printf.printf "Pretty Unicode: \\<forall> x. P x \\<Longrightarrow> \\<exists> y. Q y\\<^sub>1\\<^sup>2\\<^sup>x is %s\n"
    (unicode_of_ascii "\\<forall> x. P x \\<Longrightarrow> \\<exists> y. Q y\\<^sub>1\\<^sup>2\\<^sup>x");

  let s = "[X\\<^sub>0, X\\<^sub>1, X\\<^sup>0, X\\<^sup>+, X\\<^sub>-, X\\<^sub>1\\<^sub>2]" in
  Printf.printf "Pretty Unicode: %s is %s\n" s (unicode_of_ascii s)
