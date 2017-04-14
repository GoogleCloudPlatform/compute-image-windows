#! /bin/bash
version=$(cat google-compute-engine-windows.goospec | grep -Po '"version":\s+"\K.+(?=",)')
if [[ $? -ne 0 ]]; then
  echo "could not match version in goospec"
  exit 1
fi
GOOS=windows go build -ldflags "-X main.version=${version}" ./GCEWindowsAgent