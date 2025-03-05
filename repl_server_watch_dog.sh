#!/bin/bash
# This is a simple watch dog that ensures the server is keeping online
# It has the same parameters as the server.

echo 0 > /proc/$$/oom_score_adj
echo -1000 > /proc/$$/oom_score_adj

while true; do
    ./repl_server.sh "$@"
    exit_status=$?

    if [ $exit_status -eq 0 ]; then
        break
    fi

    echo "The server terminates with code $exit_status. Now rebooting the server..."
    sleep 1
done


