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

msi=$1
expectedsha256=$2

# Remove any existing .msi files.
rm -f *.msi

# Download .msi file
curl -O -L $msi

# Get sha256sum for downloaded file.
actualsha256=`sha256sum *.msi | cut -d' ' -f1`

# Compare sha256sum values.
if [ "$expectedsha256" != "$actualsha256" ]; then
  echo "sha256sum value not as expected. Exiting."
  exit 1
fi

# Move the .msi file to the ssh directory.
mv *.msi ssh/.
