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

using Microsoft.Win32;
using System.Collections.Generic;

namespace Common
{
  public class RegistryWriter
  {
    private readonly string registryKeyPath;
    private readonly string registryKeyName;

    public RegistryWriter(string registryKeyPath,string registryKey)
    {
      this.registryKeyPath = registryKeyPath;
      this.registryKeyName = registryKey;
    }

    /// <summary>
    /// Get the list of registry keys.
    /// </summary>
    public List<string> GetRegistryKeys()
    {
      using (RegistryKey key = Registry.LocalMachine.OpenSubKey(registryKeyPath, true))
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
    /// Add a registry key to the registry.
    /// </summary>
    public void AddRegistryKey(string registryValue)
    {
      using (RegistryKey key = Registry.LocalMachine.OpenSubKey(registryKeyPath, true) ??
          Registry.LocalMachine.CreateSubKey(registryKeyPath))
      {
        List<string> registryValues = GetRegistryKeys();
        registryValues.Add(registryValue);
        registryValues.RemoveAll(value => value == null);
        key.SetValue(registryKeyName, registryValues.ToArray(), RegistryValueKind.MultiString);
      }
    }

    /// <summary>
    /// Remove a registry key from the registry.
    /// </summary>
    private void RemoveRegistryKey(string registryValue)
    {
      List<string> registryValues = GetRegistryKeys();
      using (RegistryKey key = Registry.LocalMachine.OpenSubKey(registryKeyPath, true))
      {
        if (key != null && registryValues.Contains(registryValue))
        {
          registryValues.Remove(registryValue);
          key.SetValue(registryKeyName, registryValues.ToArray(), RegistryValueKind.MultiString);
        }
      }
    }

    /// <summary>
    /// Remove a list of registry keys from the registry.
    /// </summary>
    public void RemoveRegistryKeys(List<string> registryValues)
    {
      foreach (string registryValue in registryValues ?? new List<string>())
      {
        RemoveRegistryKey(registryValue);
      }
    }
  }
}
