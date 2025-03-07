#!/bin/bash
# This is a simple watch dog that ensures the server is keeping online
# It has the same parameters as the server.

echo 0 > /proc/$$/oom_score_adj 2> /dev/null
echo -1000 > /proc/$$/oom_score_adj 2> /dev/null
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

while true; do
    $BASE_DIR/repl_server.sh "$@"
    exit_status=$?

    if [ $exit_status -eq 0 ]; then
        break
    fi

    echo "The server terminates with code $exit_status. Now rebooting the server..."
    sleep 1
done


