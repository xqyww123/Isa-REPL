theory Isa_REPL_example
  imports Isa_REPL
begin




ML \<open>Path.explode "/tmp/repl_outputs"\<close>


ML \<open>REPL_Server.startup (Path.explode "/tmp/repl_outputs") NONE "127.0.0.1:44650"\<close>

term 1

end