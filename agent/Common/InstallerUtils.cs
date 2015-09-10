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
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.ServiceProcess;

namespace Common
{
  public static class InstallerUtils
  {
    /// <summary>
    /// Github path to download release binaries.
    /// </summary>
    private const string GITHUB_URL = @"https://github.com/GoogleCloudPlatform/compute-image-windows" +
        @"/releases/download/{0}/{1}";

    /// <summary>
    /// Installer need to set value pairs in this path to leverage Omaha.
    /// </summary>
    private const string OMAHA_REGISTRY = @"SOFTWARE\Google\Update\Clients";

    /// <summary>
    /// Installer need to set a value pair in this path to report Omaha usage.
    /// </summary>
    private const string OMAHA_STATS_REGISTRY = @"SOFTWARE\Google\Update\ClientState";

    /// <summary>
    /// Fetch Github releases and install them on local machine.
    /// </summary>
    /// <param name="version">Release version.</param>
    /// <param name="filenames">List of binary names.</param>
    /// <param name="localPath">Destination to install the binaries.</param>
    /// <param name="service">Service that need to be stopped before binary replacement.</param>
    public static void InstallBinaries(
        Version version,
        IEnumerable<string> filenames,
        string localPath,
        string service = null)
    {
      ArgumentValidator.ThrowIfNull(version, "version");
      ArgumentValidator.ThrowIfNullOrEmpty(filenames, "filenames");
      ArgumentValidator.ThrowIfNullOrEmpty(localPath, "localPath");

      FetchGithubRelease(version, filenames, localPath);

      if (!string.IsNullOrWhiteSpace(service))
      {
        using (ServiceController serviceController = new ServiceController(service))
        {
          serviceController.Stop();
          serviceController.WaitForStatus(ServiceControllerStatus.Stopped);
          ReplaceBinaries(filenames, localPath);
          serviceController.Start();
          serviceController.WaitForStatus(ServiceControllerStatus.Running);
        }
      }
      else
      {
        ReplaceBinaries(filenames, localPath);
      }
    }

    private static void FetchGithubRelease(Version version, IEnumerable<string> filenames, string localPath)
    {
      if (!Directory.Exists(localPath))
      {
        Directory.CreateDirectory(localPath);
      }

      WebClient client = new WebClient();
      foreach (string filename in filenames)
      {
        string fileUrl = string.Format(GITHUB_URL, version, filename);
        client.DownloadFile(fileUrl, string.Format(@"{0}\{1}.temp", localPath, filename));
      }
    }

    private static void ReplaceBinaries(IEnumerable<string> filenames, string localPath)
    {
      foreach (string filename in filenames)
      {
        File.Copy(
            string.Format(@"{0}\{1}.temp", localPath, filename),
            string.Format(@"{0}\{1}", localPath, filename),
            overwrite: true);
      }
    }

    /// <summary>
    /// Write the current version, the language and the application name to
    /// registry. This enables Omaha to update the specified application.
    /// </summary>
    public static void WriteUpdateKey(Guid applicationId, Version version, string applicationName = null)
    {
      ArgumentValidator.ThrowIfNullOrEmpty(applicationId, "applicationId");
      ArgumentValidator.ThrowIfNull(version, "verions");

      List<Tuple<string, object, RegistryValueKind>> registryValues =
        new List<Tuple<string, object, RegistryValueKind>>
        {
          new Tuple<string, object, RegistryValueKind>("pv", version.ToString(), RegistryValueKind.String),
          new Tuple<string, object, RegistryValueKind>("lang", "en", RegistryValueKind.String)
        };
      if (applicationName != null)
      {
        registryValues.Add(new Tuple<string, object, RegistryValueKind>(
            "name",
            applicationName,
            RegistryValueKind.String));
      }

      RegistryWriter registryWriter = new RegistryWriter(OMAHA_REGISTRY);

      // Write to subkey HKLM\SOFTWARE\Google\Update\Clients\{appID}\.
      // The appID is in format {00000000-0000-0000-0000-000000000000}.
      registryWriter.AddValueEntries(applicationId.ToString("B").ToUpper(), registryValues);
    }

    /// <summary>
    /// Write a value entry to HKLM\SOFTWARE\Google\Update\ClientState to
    /// report Omaha usage information. The name of the entry is "dr" and
    /// the value is set to "1".
    /// </summary>
    public static void WriteUpdateStatsKey(Guid applicationId)
    {
      ArgumentValidator.ThrowIfNullOrEmpty(applicationId, "applicationId");

      List<Tuple<string, object, RegistryValueKind>> registryValues =
        new List<Tuple<string, object, RegistryValueKind>>
        {
          new Tuple<string, object, RegistryValueKind>("dr", "1", RegistryValueKind.String)
        };

      RegistryWriter registryWriter = new RegistryWriter(OMAHA_STATS_REGISTRY);
      registryWriter.AddValueEntries(applicationId.ToString("B").ToUpper(), registryValues);
    }
  }
}
