theory Internal_Test
  imports Isa_REPL "Auto_Sledgehammer.Auto_Sledgehammer"
begin




ML \<open>Path.explode "/tmp/repl_outputs"\<close>

ML \<open>REPL_Server.startup (Path.explode "/tmp/repl_outputs") NONE "127.0.0.1:4477"\<close>

term 1

end
