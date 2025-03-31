theory Internal_Test
  imports Isa_REPL "Auto_Sledgehammer.Auto_Sledgehammer"
begin




ML \<open>Path.explode "/tmp/repl_outputs"\<close>

ML \<open>REPL_Server.startup (Path.explode "/home/xero/Current/MLML/cache/repl_tmps/66") NONE "127.0.0.1:4481"\<close>

term 1

end
