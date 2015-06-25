#!/usr/bin/env python

# Copyright 2015 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import base64
import copy
import datetime
import json
import time

# PyCrypto library: https://pypi.python.org/pypi/pycrypto
from Crypto.Cipher import PKCS1_OAEP
from Crypto.PublicKey import RSA
from Crypto.Util.number import long_to_bytes

# Google API Client Library for Python:
# https://developers.google.com/api-client-library/python/start/get_started
from oauth2client.client import GoogleCredentials
from googleapiclient.discovery import build


def GetCompute():
    """Get a compute oject for communicating with the Compute Engine API."""
    credentials = GoogleCredentials.get_application_default()
    compute = build('compute', 'v1', credentials=credentials)
    return compute


def GetInstance(compute, instance, zone, project):
    """Get the data for a Google Compute Engine instance."""
    cmd = compute.instances().get(instance=instance, project=project,
                                  zone=zone)
    return cmd.execute()


def GetKey():
    """Get an RSA key for encryption."""
    # This uses the PyCrypto library
    key = RSA.generate(2048)
    return key


def GetModulusExponentInBase64(key):
    """Return the public modulus and exponent for the key in bas64 encoding."""
    mod = long_to_bytes(key.n)
    exp = long_to_bytes(key.e)

    modulus = base64.b64encode(mod)
    exponent = base64.b64encode(exp)

    return modulus, exponent


def GetExpirationTimeString():
    """Return an RFC3339 UTC timestamp for 5 minutes from now."""
    utc_now = datetime.datetime.utcnow()
    # These metadata entries are one-time-use, so the expiration time does
    # not need to be very far in the future. In fact, one minute would
    # generally be sufficient. Five minutes allows for minor variations
    # between the time on the client and the time on the server.
    expire_time = utc_now + datetime.timedelta(minutes=5)
    return expire_time.strftime('%Y-%m-%dT%H:%M:%SZ')


def GetJsonString(user, modulus, exponent, email):
    """Return the JSON string object that represents the windows-keys entry."""
    expire = GetExpirationTimeString()
    data = {'userName': user,
            'modulus': modulus,
            'exponent': exponent,
            'email': email,
            'expireOn': expire}
    return json.dumps(data)


def UpdateWindowsKeys(old_metadata, metadata_entry):
    """Return updated metadata contents with the new windows-keys entry."""
    # Simply overwrites the "windows-keys" metadata entry. Production code may
    # want to append new lines to the metadata value and remove any expired
    # entries.
    new_metadata = copy.deepcopy(old_metadata)
    for item in new_metadata['items']:
        if item['key'] == 'windows-keys':
            item['value'] = metadata_entry
    return new_metadata


def UpdateInstanceMetadata(compute, instance, zone, project, new_metadata):
    """Update the instance metadata."""
    cmd = compute.instances().setMetadata(instance=instance, project=project,
                                          zone=zone, body=new_metadata)
    return cmd.execute()


def GetSerialPortFourOutput(compute, instance, zone, project):
    """Get the output from serial port 4 from the instance."""
    # Encrypted passwords are printed to COM4 on the windows server:
    port = 4
    cmd = compute.instances().getSerialPortOutput(instance=instance,
                                                  project=project,
                                                  zone=zone, port=port)
    output = cmd.execute()
    return output['contents']


def GetEncryptedPasswordFromSerialPort(serial_port_output, modulus):
    """Find and return the correct encrypted password, based on the modulus."""
    # In production code, this may need to be run multiple times if the output
    # does not yet contain the correct entry.
    output = serial_port_output.split('\n')
    for line in reversed(output):
        try:
            entry = json.loads(line)
            if modulus == entry['modulus']:
                return entry['encryptedPassword']
        except ValueError:
            pass


def DecryptPassword(encrypted_password, key):
    """Decrypt a base64 encoded encrypted password using the provided key."""
    decoded_password = base64.b64decode(encrypted_password)
    cipher = PKCS1_OAEP.new(key)
    password = cipher.decrypt(decoded_password)
    return password


def main(instance, zone, project, user, email):
    # Setup
    compute = GetCompute()
    key = GetKey()
    modulus, exponent = GetModulusExponentInBase64(key)

    # Get existing metadata
    instance_ref = GetInstance(compute, instance, zone, project)
    old_metadata = instance_ref['metadata']

    # Create and set new metadata
    metadata_entry = GetJsonString(user, modulus,
                                   exponent, email)
    new_metadata = UpdateWindowsKeys(old_metadata, metadata_entry)
    result = UpdateInstanceMetadata(compute, instance, zone, project,
                                    new_metadata)

    # For this sample code, just sleep for 30 seconds instead of checking for
    # responses. In production code, this should monitor the status of the
    # metadata update operation.
    time.sleep(30)

    # Get and decrypt password from serial port output
    serial_port_output = GetSerialPortFourOutput(compute, instance,
                                                 zone, project)
    enc_password = GetEncryptedPasswordFromSerialPort(serial_port_output,
                                                      modulus)
    password = DecryptPassword(enc_password, key)

    # Display the username, password and IP address for the instance
    print 'Username:   {0}'.format(user)
    print 'Password:   {0}'.format(password)
    ip = instance_ref['networkInterfaces'][0]['accessConfigs'][0]['natIP']
    print 'IP Address: {0}'.format(ip)


if __name__ == '__main__':
    instance = 'my-instance'
    zone = 'us-central1-a'
    project = 'my-project'
    user = 'example-user'
    email = 'user@example.com'
    main(instance, zone, project, user, email)
