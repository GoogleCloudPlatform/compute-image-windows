﻿/*
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
                registryValues.Add(registryValue);
                registryValues.RemoveAll(value => value == null);
                key.SetValue(registryKeyName, registryValues.ToArray(), RegistryValueKind.MultiString);
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
    }
}
