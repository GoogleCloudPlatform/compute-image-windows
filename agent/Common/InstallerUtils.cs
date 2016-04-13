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

        private const string TempFileExtension = @".temp";

        /// <summary>
        /// Download source from GitHub to a provided file location.
        /// </summary>
        private static void FetchGitHubFiles(
            string gitHubPath,
            IEnumerable<string> fileNames,
            string destPath)
        {
            if (!Directory.Exists(destPath))
            {
                Directory.CreateDirectory(destPath);
            }

            WebClient client = new WebClient();
            foreach (string fileName in fileNames)
            {
                string fileUrl = string.Format("{0}/{1}/{2}", GitHubUrl, gitHubPath, fileName);
                client.DownloadFile(fileUrl, string.Format(@"{0}\{1}{2}", destPath, fileName, TempFileExtension));
            }
        }

        /// <summary>
        /// Download source from GitHub.
        /// </summary>
        public static void GetSources(Version version, string destPath)
        {
            string destination = Path.Combine(destPath, SourcePath);
            string fileName = string.Format("{0}.zip", version);
            string[] fileNames = { fileName };
            FetchGitHubFiles(SourceUrl, fileNames, destPath);

            if (Directory.Exists(destination))
            {
                Directory.Delete(destination, recursive: true);
            }

            string zipFile = Path.Combine(destPath, fileName + TempFileExtension);
            ZipFile.ExtractToDirectory(zipFile, destination);
            File.Delete(zipFile);
        }

        /// <summary>
        /// Clean up temporary files.
        /// </summary>
        public static void CleanUp(IEnumerable<string> fileNames, string path)
        {
            foreach (string fileName in fileNames)
            {
                if (File.Exists(Path.Combine(path, fileName + TempFileExtension)))
                {
                    File.Delete(Path.Combine(path, fileName + TempFileExtension));
                }
            }
        }

        /// <summary>
        /// Generate a new temporary directory name to store existing binaries.
        /// </summary>
        public static string GetTempDirName()
        {
            string dirName;
            do
            {
                dirName = string.Format("{0}{1}", Path.GetTempPath(), Guid.NewGuid());
            }
            while (Directory.Exists(dirName));
            return dirName;
        }

        public static void DeleteDir(string path)
        {
            try
            {
                Directory.Delete(path, recursive: true);
            }
            catch
            {
                Logger.Warning("Failed to delete directory: {0}.", path);
            }
        }

        /// <summary>
        /// Replace files in the destination directory.
        /// </summary>
        public static void ReplaceFiles(
            IEnumerable<string> fileNames,
            string sourcePath,
            string destPath,
            string backupPath,
            string suffix)
        {
            if (!Directory.Exists(backupPath))
            {
                Directory.CreateDirectory(backupPath);
            }

            // Backup previous version
            foreach (string fileName in fileNames)
            {
                if (File.Exists(Path.Combine(destPath, fileName)))
                {
                    File.Move(Path.Combine(destPath, fileName), Path.Combine(backupPath, fileName));
                }
            }

            foreach (string fileName in fileNames)
            {
                if (File.Exists(Path.Combine(destPath, fileName + suffix)))
                {
                    File.Move(Path.Combine(sourcePath, fileName + suffix), Path.Combine(destPath, fileName));
                }
            }
        }

        /// <summary>
        /// Rollback files from previous version.
        /// </summary>
        public static void Rollback(
            IEnumerable<string> fileNames,
            string destPath,
            string backupPath,
            string service = null)
        {
            // Recover previous binaries.
            foreach (string fileName in fileNames)
            {
                if (File.Exists(Path.Combine(backupPath, fileName)))
                {
                    File.Move(Path.Combine(backupPath, fileName), Path.Combine(destPath, fileName));
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
        /// Fetch GitHub releases and install them on local machine.
        /// </summary>
        /// <param name="version">Release version.</param>
        /// <param name="fileNames">List of binary names.</param>
        /// <param name="destPath">Destination to install the binaries.</param>
        /// <param name="service">
        /// Service that need to be stopped before binary replacement.
        /// </param>
        public static void InstallBinaries(
            Version version,
            IEnumerable<string> fileNames,
            string destPath,
            string backupPath,
            string service = null)
        {
            ArgumentValidator.ThrowIfNull(version, "version");
            ArgumentValidator.ThrowIfNullOrEmpty(fileNames, "fileNames");
            ArgumentValidator.ThrowIfNullOrEmpty(destPath, "destPath");
            ArgumentValidator.ThrowIfNullOrEmpty(destPath, "backupPath");

            FetchGitHubFiles(ReleaseUrl + version, fileNames, destPath);

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

                        ReplaceFiles(fileNames, destPath, destPath, backupPath, suffix: TempFileExtension);
                        serviceController.Start();
                        serviceController.WaitForStatus(ServiceControllerStatus.Running);
                    }
                }
                else
                {
                    ReplaceFiles(fileNames, destPath, destPath, backupPath, suffix: TempFileExtension);
                }
            }
            catch
            {
                Rollback(fileNames, destPath, backupPath, service: service);
                throw;
            }

            CleanUp(fileNames, destPath);
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
