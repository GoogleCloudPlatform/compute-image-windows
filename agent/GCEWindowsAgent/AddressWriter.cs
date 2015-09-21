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
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using Google.ComputeEngine.Common;

namespace Google.ComputeEngine.Agent
{
    public sealed class AddressWriter : IAgentWriter<List<IPAddress>>
    {
        private const string RegistryKeyPath = @"SOFTWARE\Google\ComputeEngine";
        private const string RegistryKey = "ForwardedIps";
        private readonly RegistryWriter registryWriter = new RegistryWriter(RegistryKeyPath);

        private static int GetPrimaryInterfaceIndex()
        {
            foreach (NetworkInterface networkInterface in NetworkInterface.GetAllNetworkInterfaces())
            {
                if ((networkInterface.NetworkInterfaceType == NetworkInterfaceType.Ethernet)
                    && networkInterface.Supports(NetworkInterfaceComponent.IPv4))
                {
                    return networkInterface.GetIPProperties().GetIPv4Properties().Index;
                }
            }

            throw new InvalidOperationException("Unable to find primary network interface.");
        }

        private static void AddAddress(IPAddress addressToAdd)
        {
            int myNteContext = 0;
            int myNteInstance = 0;

            int interfaceIndex = GetPrimaryInterfaceIndex();
            IntPtr ptrMyNTEContext = new IntPtr(myNteContext);
            IntPtr ptrMyNTEInstance = new IntPtr(myNteInstance);
            int address = BitConverter.ToInt32(addressToAdd.GetAddressBytes(), 0);
            int mask = BitConverter.ToInt32(IPAddress.None.GetAddressBytes(), 0);

            int result = NativeMethods.AddIPAddress(
                address,
                mask,
                interfaceIndex,
                out ptrMyNTEContext,
                out ptrMyNTEInstance);
            if (result != 0)
            {
                Logger.Error(
                    "Failed to add address {0} to interface index {1} due to error {2}",
                    addressToAdd,
                    interfaceIndex,
                    result);
                throw new System.ComponentModel.Win32Exception(result);
            }
        }

        private void AddAddresses(IEnumerable<IPAddress> toAdd)
        {
            foreach (IPAddress address in toAdd)
            {
                AddAddress(address);
                registryWriter.AddMultiStringValue(RegistryKey, address.ToString());
            }
        }

        private static IntPtr FindAddressContextInAddressList(
            NativeMethods.IP_ADDR_STRING firstIpAddrString,
            IPAddress addressToFind)
        {
            IntPtr result = IntPtr.Zero;
            NativeMethods.IP_ADDR_STRING ipAddrString = firstIpAddrString;
            while (true)
            {
                IPAddress address = IPAddress.Parse(ipAddrString.IpAddress.Address);
                if (address.Equals(addressToFind))
                {
                    result = new IntPtr(ipAddrString.Context);
                    break;
                }

                if (ipAddrString.Next == IntPtr.Zero)
                {
                    break;
                }

                ipAddrString = (NativeMethods.IP_ADDR_STRING)Marshal.PtrToStructure(
                    ipAddrString.Next, typeof(NativeMethods.IP_ADDR_STRING));
            }

            return result;
        }

        private static IntPtr FindAddressContextInBuffer(IntPtr ipAdapterInfoBuffer, IPAddress addressToFind)
        {
            IntPtr result = IntPtr.Zero;
            do
            {
                NativeMethods.IP_ADAPTER_INFO entry = (NativeMethods.IP_ADAPTER_INFO)Marshal.PtrToStructure(
                    ipAdapterInfoBuffer, typeof(NativeMethods.IP_ADAPTER_INFO));
                result = FindAddressContextInAddressList(entry.IpAddressList, addressToFind);
                if (result != IntPtr.Zero)
                {
                    break;
                }

                ipAdapterInfoBuffer = entry.Next;
            }
            while (ipAdapterInfoBuffer != IntPtr.Zero);

            return result;
        }

        private static IntPtr FindAddressContext(IPAddress addressToFind)
        {
            // Get the required buffer size
            int bufferSize = 0;
            NativeMethods.GetAdaptersInfo(IntPtr.Zero, ref bufferSize);

            // Allocate the buffer
            IntPtr buffer = Marshal.AllocHGlobal(bufferSize);

            // Retrieve the table.
            try
            {
                int result = NativeMethods.GetAdaptersInfo(buffer, ref bufferSize);
                if (result != 0)
                {
                    throw new System.ComponentModel.Win32Exception(result);
                }

                // Walk over the buffer and locate the matching context token.
                IntPtr nteContext = FindAddressContextInBuffer(buffer, addressToFind);
                if (nteContext == IntPtr.Zero)
                {
                    string message = string.Format("Unable to locate NTEContext for address {0}", addressToFind);
                    throw new InvalidOperationException(message);
                }
                return nteContext;
            }
            finally
            {
                if (buffer != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(buffer);
                }
            }
        }

        private static void RemoveAddress(IPAddress addressToRemove)
        {
            int interfaceIndex = GetPrimaryInterfaceIndex();

            // The Net Table Entry context for the IP address.
            IntPtr nteContext = FindAddressContext(addressToRemove);
            int result = NativeMethods.DeleteIPAddress(nteContext);
            if (result != 0)
            {
                Logger.Error("Failed to delete address {0} due to error {1}", addressToRemove, result);
                throw new System.ComponentModel.Win32Exception(result);
            }
        }

        private void RemoveAddresses(IEnumerable<IPAddress> toRemove)
        {
            foreach (IPAddress address in toRemove)
            {
                RemoveAddress(address);
            }
        }

        private string GetJoinStringOrNone<T>(List<T> items)
        {
            if (items.Count == 0)
            {
                return "None";
            }

            return string.Join(", ", items);
        }

        private void LogForwardedIpsChanges(
            List<IPAddress> configured,
            List<IPAddress> desired,
            List<IPAddress> toAdd,
            List<IPAddress> toRemove)
        {
            if (toAdd.Count == 0 && toRemove.Count == 0)
            {
                return;
            }

            Logger.Info(
                "Changing forwarded IPs from {0} to {1} by adding {2} and removing {3}",
                GetJoinStringOrNone(configured),
                GetJoinStringOrNone(desired),
                GetJoinStringOrNone(toAdd),
                GetJoinStringOrNone(toRemove));
        }

        private static IPAddress ConvertStringToIpAddress(string ip)
        {
            try
            {
                return IPAddress.Parse(ip);
            }
            catch (FormatException)
            {
                Logger.Info("Caught exception in GetRegistryAddresses. Could not parse IP: {0}", ip);
                return null;
            }
        }

        public void SetMetadata(List<IPAddress> metadata)
        {
            List<string> registryKeys = registryWriter.GetMultiStringValue(RegistryKey);
            List<IPAddress> registryForwardedIps = registryKeys.ConvertAll<IPAddress>(ConvertStringToIpAddress);
            List<IPAddress> addressesConfigured = AddressSystemReader.GetAddresses();
            List<IPAddress> toAdd = new List<IPAddress>(metadata.Except(addressesConfigured));
            List<IPAddress> toRemove = new List<IPAddress>(registryForwardedIps.Except(metadata));
            List<string> metadataStrings = metadata.ConvertAll<string>(ip => ip.ToString());
            List<string> toRemoveFromRegistry = new List<string>(registryKeys.Except(metadataStrings));
            LogForwardedIpsChanges(addressesConfigured, metadata, toAdd, toRemove);
            AddAddresses(toAdd);
            RemoveAddresses(toRemove);
            registryWriter.RemoveMultiStringValues(RegistryKey, toRemoveFromRegistry);
        }
    }
}
