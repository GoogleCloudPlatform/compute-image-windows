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
using Microsoft.Win32;

namespace Google.ComputeEngine.Common
{
    public sealed class RegistryWriter
    {
        private readonly string registryKeyPath;

        public RegistryWriter(string registryKeyPath)
        {
            ArgumentValidator.ThrowIfNullOrEmpty(registryKeyPath, "registryKeyPath");
            this.registryKeyPath = registryKeyPath;
        }

        /// <summary>
        /// Get the list of values of a MultiString value entry.
        /// </summary>
        public List<string> GetMultiStringValue(string registryKeyName)
        {
            ArgumentValidator.ThrowIfNullOrEmpty(registryKeyName, "registryKeyName");

            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(this.registryKeyPath, true))
            {
                string[] values = new string[] { };
                if (key != null)
                {
                    values = (string[])key.GetValue(registryKeyName, new string[] { });
                }
                return new List<string>(values);
            }
        }

        /// <summary>
        /// Add a value key to the MultiString value entry.
        /// </summary>
        public void AddMultiStringValue(string registryKeyName, string registryValue)
        {
            ArgumentValidator.ThrowIfNullOrEmpty(registryKeyName, "registryKeyName");

            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(this.registryKeyPath, true) ??
                Registry.LocalMachine.CreateSubKey(this.registryKeyPath))
            {
                List<string> registryValues = GetMultiStringValue(registryKeyName);
                if (registryValues.Contains(registryValue))
                {
                    return;
                }
                registryValues.Add(registryValue);
                registryValues.RemoveAll(value => value == null);
                key.SetValue(registryKeyName, registryValues.ToArray(), RegistryValueKind.MultiString);
            }
        }

        /// <summary>
        /// Set a value entry in the specified subkey.
        /// </summary>
        public void SetStringValue(string subKey, string name, string value)
        {
            ArgumentValidator.ThrowIfNullOrEmpty(subKey, "subKey");
            ArgumentValidator.ThrowIfNullOrEmpty(name, "name");

            string registrykey = string.Format(@"{0}\{1}", this.registryKeyPath, subKey);
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(registrykey, true) ??
                Registry.LocalMachine.CreateSubKey(registrykey))
            {
                key.SetValue(name, value, RegistryValueKind.String);
            }
        }

        /// <summary>
        /// Remove a value from a MultiString value entry.
        /// </summary>
        private void RemoveMultiStringValue(string registryKeyName, string registryValue)
        {
            ArgumentValidator.ThrowIfNullOrEmpty(registryKeyName, "registryKeyName");

            List<string> registryValues = GetMultiStringValue(registryKeyName);
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(this.registryKeyPath, true))
            {
                if (key != null && registryValues.Contains(registryValue))
                {
                    registryValues.Remove(registryValue);
                    key.SetValue(registryKeyName, registryValues.ToArray(), RegistryValueKind.MultiString);
                }
            }
        }

        /// <summary>
        /// Remove a list of values from a MultiString value entry.
        /// </summary>
        public void RemoveMultiStringValues(string registryKeyName, List<string> registryValues)
        {
            ArgumentValidator.ThrowIfNullOrEmpty(registryKeyName, "registryKeyName");

            foreach (string registryValue in registryValues ?? new List<string>())
            {
                RemoveMultiStringValue(registryKeyName, registryValue);
            }
        }

        /// <summary>
        /// Write a list of values to the sub key.
        /// </summary>
        /// <param name="subKey">Name of the sub-key.</param>
        /// <param name="registryValues">
        /// A list of registry values. Each value is a 3-tuple: entry name,
        /// entry value and entry type.
        /// </param>
        public void AddValueEntries(string subKey, IEnumerable<Tuple<string, object, RegistryValueKind>> registryValues)
        {
            ArgumentValidator.ThrowIfNullOrEmpty(subKey, "subKey");
            ArgumentValidator.ThrowIfNullOrEmpty(registryValues, "registryValues");

            string registrykey = string.Format(@"{0}\{1}", this.registryKeyPath, subKey);
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(registrykey, true) ??
                Registry.LocalMachine.CreateSubKey(registrykey))
            {
                foreach (Tuple<string, object, RegistryValueKind> registryValue in registryValues)
                {
                    key.SetValue(registryValue.Item1, registryValue.Item2, registryValue.Item3);
                }
            }
        }
    }
}
