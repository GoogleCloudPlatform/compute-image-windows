#! /bin/bash
version=$(cat google-compute-engine-windows.goospec | sed -nE 's/.*"version":.*"(.+)".*/\1/p')
if [[ $? -ne 0 ]]; then
  echo "could not match version in goospec"
  exit 1
fi
GOOS=windows go build -ldflags "-X main.version=${version}" ./GCEWindowsAgent
