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
using System.IO;
using System.IO.Compression;
using System.Management;
using System.Net;
using System.ServiceProcess;
using Microsoft.Win32;

namespace Google.ComputeEngine.Common
{
    public static class InstallerUtils
    {
        /// <summary>
        /// GitHub path to download release binaries.
        /// </summary>
        private const string GitHubUrl = @"https://github.com/GoogleCloudPlatform/compute-image-windows";

        /// <summary>
        /// The path to download GitHub release.
        /// </summary>
        private const string ReleaseUrl = @"releases/download/";

        /// <summary>
        /// The path to download GitHub source.
        /// </summary>
        private const string SourceUrl = @"archive";

        /// <summary>
        /// The local directory that source are download to.
        /// </summary>
        public const string SourcePath = @"github_source";

        /// <summary>
        /// Installer need to set value pairs in this path to leverage Omaha.
        /// </summary>
        private const string OmahaClients = @"SOFTWARE\Google\Update\Clients";

        /// <summary>
        /// Installer need to set a value pair in this path to report Omaha
        /// usage.
        /// </summary>
        private const string OmahaClientState = @"SOFTWARE\Google\Update\ClientState";

        private const string BackupFileExtension = @".backup";

        private const string TempFileExtension = @".temp";


        /// <summary>
        /// Fetch GitHub releases and install them on local machine.
        /// </summary>
        /// <param name="version">Release version.</param>
        /// <param name="filenames">List of binary names.</param>
        /// <param name="localPath">Destination to install the binaries.</param>
        /// <param name="service">
        /// Service that need to be stopped before binary
        /// replacement.
        /// </param>
        public static void InstallBinaries(
            Version version,
            IEnumerable<string> filenames,
            string localPath,
            string service = null)
        {
            ArgumentValidator.ThrowIfNull(version, "version");
            ArgumentValidator.ThrowIfNullOrEmpty(filenames, "filenames");
            ArgumentValidator.ThrowIfNullOrEmpty(localPath, "localPath");

            FetchGitHubFiles(ReleaseUrl + version, filenames, localPath);

            try
            {
                if (!string.IsNullOrWhiteSpace(service))
                {
                    using (ServiceController serviceController = new ServiceController(service))
                    {
                        if (serviceController.Status != ServiceControllerStatus.Stopped)
                        {
                            serviceController.Stop();
                            serviceController.WaitForStatus(ServiceControllerStatus.Stopped);
                        }

                        ReplaceFiles(filenames, localPath, localPath, suffix: ".temp");
                        serviceController.Start();
                        serviceController.WaitForStatus(ServiceControllerStatus.Running);
                    }
                }
                else
                {
                    ReplaceFiles(filenames, localPath, localPath, suffix: ".temp");
                }
            }
            catch
            {
                Rollback(filenames, localPath, service);
                throw;
            }

            CleanUp(filenames, localPath);
        }

        /// <summary>
        /// Download source from GitHub.
        /// </summary>
        public static void GetSources(Version version, string localPath)
        {
            string[] filenames = { string.Format("{0}.zip", version) };
            FetchGitHubFiles(SourceUrl, filenames, localPath);

            string destination = Path.Combine(localPath, SourcePath);

            if (Directory.Exists(destination))
            {
                Directory.Delete(destination, recursive: true);
            }

            string zipFile = Path.Combine(localPath, filenames[0] + TempFileExtension);
            ZipFile.ExtractToDirectory(zipFile, destination);
            File.Delete(zipFile);
        }

        private static void FetchGitHubFiles(
            string githubPath,
            IEnumerable<string> filenames,
            string localPath)
        {
            if (!Directory.Exists(localPath))
            {
                Directory.CreateDirectory(localPath);
            }

            WebClient client = new WebClient();
            foreach (string filename in filenames)
            {
                string fileUrl = string.Format("{0}/{1}/{2}", GitHubUrl, githubPath, filename);
                client.DownloadFile(fileUrl, string.Format(@"{0}\{1}{2}", localPath, filename, TempFileExtension));
            }
        }

        /// <summary>
        /// Replace files in the destination directory.
        /// </summary>
        public static void ReplaceFiles(
            IEnumerable<string> filenames,
            string original,
            string destination,
            string suffix)
        {
            // Backup previous version
            foreach (string filename in filenames)
            {
                if (File.Exists(Path.Combine(destination, filename)))
                {
                    File.Copy(
                        Path.Combine(destination, filename),
                        Path.Combine(destination, filename + BackupFileExtension),
                        overwrite: true);
                }
            }

            foreach (string filename in filenames)
            {
                File.Copy(
                    Path.Combine(original, filename + suffix),
                    Path.Combine(destination, filename),
                    overwrite: true);
            }
        }

        /// <summary>
        /// Rollback files from previous version.
        /// </summary>
        public static void Rollback(IEnumerable<string> filenames, string path, string service = null)
        {
            // recover previous binaries
            foreach (string filename in filenames)
            {
                if (File.Exists(Path.Combine(path, filename + BackupFileExtension)))
                {
                    File.Copy(
                        Path.Combine(path, filename + BackupFileExtension),
                        Path.Combine(path, filename),
                        overwrite: true);
                }
            }

            if (!string.IsNullOrWhiteSpace(service))
            {
                using (ServiceController serviceController = new ServiceController(service))
                {
                    if (serviceController.Status != ServiceControllerStatus.Running)
                    {
                        serviceController.Start();
                        serviceController.WaitForStatus(ServiceControllerStatus.Running);
                    }
                }
            }
        }

        /// <summary>
        /// Clean up backup files and temp files.
        /// </summary>
        public static void CleanUp(IEnumerable<string> filenames, string path)
        {
            foreach (string filename in filenames)
            {
                string tempFile = Path.Combine(path, filename + BackupFileExtension);
                if (File.Exists(tempFile))
                {
                    File.Delete(tempFile);
                }

                tempFile = Path.Combine(path, filename + TempFileExtension);
                if (File.Exists(tempFile))
                {
                    File.Delete(tempFile);
                }
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

            RegistryWriter registryWriter = new RegistryWriter(OmahaClients);

            // The appID is in format {00000000-0000-0000-0000-000000000000}.
            registryWriter.AddValueEntries(applicationId.ToString("B").ToUpper(), registryValues);

            registryWriter = new RegistryWriter(OmahaClientState);

            // Set to disabled by default to prevent race condition.
            registryWriter.SetStringValue(applicationId.ToString("B").ToUpper(), "ap", "disabled");
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

            RegistryWriter registryWriter = new RegistryWriter(OmahaClientState);

            // The appID is in format {00000000-0000-0000-0000-000000000000}.
            registryWriter.AddValueEntries(applicationId.ToString("B").ToUpper(), registryValues);
        }

        /// <summary>
        /// Register a Win32 service during installation.
        /// </summary>
        public static void RegisterService(string path, string name, string displayName)
        {
            Logger.Info("Registring Service {0}.", displayName);
            ManagementClass managementInstance = new ManagementClass("Win32_Service");

            // The signature of Create method:
            // uint32 Create (
            //     [in] string  Name,
            //     [in] string  DisplayName,
            //     [in] string  PathName,
            //     [in] uint8   ServiceType,
            //     [in] uint8   ErrorControl,
            //     [in] string  StartMode,
            //     [in] boolean DesktopInteract,
            //     [in] string  StartName,
            //     [in] string  StartPassword,
            //     [in] string  LoadOrderGroup,
            //     [in] string  LoadOrderGroupDependencies[],
            //     [in] string  ServiceDependencies[]
            // );
            object[] arguments =
            {
                name,
                displayName,
                path,
                (uint)ServiceType.Win32OwnProcess,
                (uint)0,
                ServiceStartMode.Automatic.ToString(),
                false,
                null,
                null,
                null,
                null,
                null
            };

            managementInstance.InvokeMethod("Create", arguments);
        }
    }
}
