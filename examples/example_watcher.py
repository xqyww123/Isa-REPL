#!/usr/bin/env python3
from IsaREPL import Client
import threading
import time

def handler(client_id, status):
    is_live, errors = status
    print(f"Client {client_id} is {'' if is_live else 'not '}live. Errors: {errors}")
Client.install_watcher('127.0.0.1:6666', handler, interval=1)

def work1():
    client2 = Client('127.0.0.1:6666', 'HOL')
    print(f"Client {client2.client_id} ({client2.cin.name}, {client2.cout.name}) is going to sleep for 10 seconds")
    client2.run_ML(None, "(OS.Process.sleep (Time.fromSeconds 10); ())")


def work2():
    client3 = Client('127.0.0.1:6666', 'HOL')
    print(f"Client {client3.client_id} ({client3.cin.name}, {client3.cout.name}) is going to crash the stack")
    try:
        client3.run_ML(None, "let fun f x = f (f x) in OS.Process.sleep (Time.fromSeconds 3); f 1; () end")
    except:
        pass

def work3():
    client4 = Client('127.0.0.1:6666', 'HOL')
    print(f"Client {client4.client_id} ({client4.cin.name}, {client4.cout.name}) is going to throw an error")
    try:
        client4.run_ML(None, "(OS.Process.sleep (Time.fromSeconds 2); error \"Error in client4\")")
    except:
        pass

thread1 = threading.Thread(target=work1)
thread2 = threading.Thread(target=work2)
thread3 = threading.Thread(target=work3)
thread1.start()
thread2.start()
thread3.start()

time.sleep(15)