import asyncio
from IsaREPL import Client

async def main():
    async with Client('127.0.0.1:6666', 'HOL') as c:
        with open('./contrib/Isabelle2024/src/HOL/Library/Multiset.thy', 'r') as f:
            src = f.read()

        await c.set_register_thy(False)
        ret = await c.eval(src, import_dir='./contrib/Isabelle2024/src/HOL/Library', base_dir='./contrib/Isabelle2024/src/HOL/Library')
        print(ret)

asyncio.run(main())
