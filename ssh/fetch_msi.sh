#!/bin/bash

# Should be run from the compute-image-windows directory.
# Usage:
#   ./ssh/fetch_msi.sh <url> <sha256sum>
#
# Description:
#   Downloads a .msi file from the given URL and compares the sha256sum
#   of the downloaded file with the given sha256sum value. If the hashes
#   match, the msi will be moved into the ssh directory for packaging. If
#   they do not match, this will display an error and exit.

msifilename=$1
msiurl=$2
expectedsha256=$3

# Remove any existing .msi files.
rm -f *.msi
rm -f ssh/*.msi

# Download .msi file
curl -o $msifilename -L $msiurl

# Get sha256sum for downloaded file.
actualsha256=`sha256sum $msifilename | cut -d' ' -f1`

# Compare sha256sum values.
if [ "$expectedsha256" != "$actualsha256" ]; then
  echo "sha256sum value not as expected. Exiting."
  exit 1
fi

# Move the .msi file to the ssh directory.
mv $msifilename ssh/$msifilename
