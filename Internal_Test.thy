theory Internal_Test
  imports Isa_REPL "Auto_Sledgehammer.Auto_Sledgehammer"
begin

ML \<open>Synchronized.change REPL.global_theories (
        Symtab.update ("Transport.Binary_Relations_Reflexive", @{theory Binary_Relations_Reflexive})
     #> Symtab.update ("Transport.Binary_Relations_Transitive", @{theory Binary_Relations_Transitive}))\<close>
 

ML \<open>Path.explode "/tmp/repl_outputs"\<close>

ML \<open>REPL_Server.startup (Path.explode "/home/xero/Current/MLML/cache/repl_tmps/66") NONE "127.0.0.1:4487"\<close>

term 1

end
