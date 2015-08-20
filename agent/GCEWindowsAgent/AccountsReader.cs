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

using Common;
using System;
using System.Collections.Generic;

namespace GCEAgent
{
  /// <summary>
  /// Reads and parses user account information from GCE's metadata service.
  /// </summary>
  public class AccountsReader : AgentReader<List<WindowsKey>>
  {
    public AccountsReader() { }

    /// <summary>
    /// Given the windows-keys metadata attribute, return a list of WindowsKey
    /// objects. Only add WindowsKey objects to the list that are not expired.
    /// </summary>
    /// <param name="windowsKeys">
    /// The metadata response for the windows-keys metadata attrbute.
    /// </param>
    /// <returns>A list of WindowsKey objects that are not expired.</returns>
    private List<WindowsKey> ParseWindowsKeys(string windowsKeys)
    {
      List<WindowsKey> windowsKeysList = new List<WindowsKey>();
      if (string.IsNullOrEmpty(windowsKeys))
      {
        return windowsKeysList;
      }

      foreach (string windowsKeyString in windowsKeys.Split(Environment.NewLine.ToCharArray()))
      {
        WindowsKey windowsKey = WindowsKey.DeserializeWindowsKey(windowsKeyString);

        if (windowsKey != null
            && !string.IsNullOrEmpty(windowsKey.Exponent)
            && !string.IsNullOrEmpty(windowsKey.Modulus)
            && !string.IsNullOrEmpty(windowsKey.UserName)
            && !windowsKey.HasExpired())
        {
          windowsKeysList.Add(windowsKey);
        }
      }
      return windowsKeysList;
    }

    public List<WindowsKey> GetMetadata(MetadataJson metadata)
    {
      try
      {
        string windowsKeys = metadata.Instance.Attributes.WindowsKeys;
        return ParseWindowsKeys(windowsKeys);
      }
      catch (NullReferenceException)
      {
        return null;
      }
    }

    public bool CompareMetadata(List<WindowsKey> oldMetadata, List<WindowsKey> newMetadata)
    {
      if (oldMetadata == null || newMetadata == null)
      {
        return oldMetadata == null && newMetadata == null;
      }
      return new HashSet<WindowsKey>(oldMetadata).SetEquals(newMetadata);
    }

    public bool IsEnabled(MetadataJson metadata)
    {
      try
      {
        return !metadata.Instance.Attributes.DisableAccountManager;
      }
      catch (NullReferenceException)
      {
        return true;
      }
    }
  }
}
