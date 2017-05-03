#!/bin/bash

if [ -n "$(gofmt -l $(go list -f {{.Dir}} ./...| grep -v /vendor/))" ]; then
    echo "Go code is not formatted:"
    gofmt -d $(go list -f {{.Dir}} ./...| grep -v /vendor/)
    exit 1
fi
