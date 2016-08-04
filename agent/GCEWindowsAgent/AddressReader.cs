/*
 * Copyright 2015 Google Inc. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

using System;
using System.Collections.Generic;
using System.Net;
using Google.ComputeEngine.Common;
using System.Net.NetworkInformation;
using System.Linq;

namespace Google.ComputeEngine.Agent
{
    /// <summary>
    /// Reads and parses address information from GCE's metadata service.
    /// </summary>
    public sealed class AddressReader : IAgentReader<Dictionary<PhysicalAddress, List<IPAddress>>>
    {
        private List<IPAddress> ParseForwardIpsResult(string[] forwardedIps)
        {
            List<IPAddress> addresses = new List<IPAddress>();
            foreach (string ip in forwardedIps)
            {
                if (!string.IsNullOrEmpty(ip))
                {
                    try
                    {
                        addresses.Add(IPAddress.Parse(ip));
                    }
                    catch (FormatException)
                    {
                        Logger.Info("Caught exception in ParseForwardIpsResult. Could not parse IP: {0}", ip);
                    }
                }
            }
            return addresses;
        }

        public Dictionary<PhysicalAddress, List<IPAddress>> GetMetadata(MetadataJson metadata)
        {
            Dictionary<PhysicalAddress, List<IPAddress>> data = new Dictionary<PhysicalAddress, List<IPAddress>>();

            foreach (NetworkInterfacesJson entry in metadata.Instance.NetworkInterfaces)
            {
                PhysicalAddress mac = PhysicalAddress.Parse(entry.MAC);
                data.Add(mac, ParseForwardIpsResult(entry.ForwardedIps));
            }
            return data;
        }

        public bool CompareMetadata(Dictionary<PhysicalAddress, List<IPAddress>> oldMetadata, Dictionary<PhysicalAddress, List<IPAddress>> newMetadata)
        {
            if (oldMetadata == null || newMetadata == null)
            {
                return oldMetadata == null && newMetadata == null;
            }
            return oldMetadata.Count == newMetadata.Count && !oldMetadata.Except(newMetadata).Any(); ;
        }

        public bool IsEnabled(MetadataJson metadata)
        {
            try
            {
                return !metadata.Instance.Attributes.DisableAddressManager;
            }
            catch (NullReferenceException)
            {
                return true;
            }
        }
    }
}
