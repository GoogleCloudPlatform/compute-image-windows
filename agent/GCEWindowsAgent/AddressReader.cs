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
using System.Net;

namespace GCEAgent
{
  /// <summary>
  /// Reads and parses address information from GCE's metadata service.
  /// </summary>
  public class AddressReader : AgentReader<List<IPAddress>>
  {
    public AddressReader() { }

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

    public List<IPAddress> GetMetadata(MetadataJson metadata)
    {
      try
      {
        string[] forwardedIps = metadata.Instance.NetworkInterfaces[0].ForwardedIps;
        return ParseForwardIpsResult(forwardedIps);
      }
      catch (NullReferenceException)
      {
        return null;
      }
    }

    public bool CompareMetadata(List<IPAddress> oldMetadata, List<IPAddress> newMetadata)
    {
      if (oldMetadata == null || newMetadata == null)
      {
        return oldMetadata == null && newMetadata == null;
      }
      return new HashSet<IPAddress>(oldMetadata).SetEquals(newMetadata);
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
