from IsaREPL import Client

c = Client('127.0.0.1:6666', 'HOL')

with open('./contrib/Isabelle2024/src/HOL/Library/Multiset.thy', 'r') as f:
    src = f.read()

c.set_register_thy(False)
ret = c.eval(src, import_dir='./contrib/Isabelle2024/src/HOL/Library', base_dir='./contrib/Isabelle2024/src/HOL/Library')
print(ret)