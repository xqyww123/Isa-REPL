theory Isa_REPL_example
  imports Isa_REPL
begin




ML \<open>Path.explode "/tmp/repl_outputs"\<close>


ML \<open>Isabelle_Thread.join (REPL_Server.startup (Path.explode "/tmp/repl_outputs") NONE "127.0.0.1:4460")\<close>

term 1

end