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
using System.IO;
using System.Linq;
using System.Reflection;
using System.ServiceProcess;
using Google.ComputeEngine.Common;

namespace Google.ComputeEngine.Agent.Installer
{
    public class Installer
    {
        private const string ComputeEnginePath = @"C:\Program Files\Google\Compute Engine";
        private const string ServiceDisplayName = @"Google Compute Engine Agent";
        private const string ServiceName = @"GCEAgent";
        private const string ApplicationName = @"GCE Windows Agent";
        private const string SysprepDirectory = @"sysprep";
        private static readonly string AgentPath = string.Format(@"{0}\agent", ComputeEnginePath);

        /// <summary>
        /// Application ID used by the Omaha service.
        /// </summary>
        private static readonly Guid ApplicationId = new Guid("3FCD4520-3859-4183-866E-C54153A286EB");

        /// <summary>
        /// Current version of the GCE Windows agent.
        /// </summary>
        private static readonly Version ReleaseVersion = Assembly.GetExecutingAssembly().GetName().Version;

        /// <summary>
        /// GCE Agent executables and dynamic libraries.
        /// </summary>
        private static readonly string[] AgentBinaries = new string[]
        {
            "GCEWindowsAgent.exe",
            "GCEMetadataScripts.exe",
            "Common.dll"
        };

        private static Assembly ResolveEventHandler(object sender, ResolveEventArgs args)
        {
            Assembly executingAssembly = Assembly.GetExecutingAssembly();
            string assemblyName = string.Format("{0}.dll", new AssemblyName(args.Name).Name);
            string resourceName = executingAssembly.GetManifestResourceNames()
                .FirstOrDefault(name => name.EndsWith(assemblyName));

            if (resourceName == null)
            {
                return null;
            }

            using (Stream stream = executingAssembly.GetManifestResourceStream(resourceName))
            {
                byte[] assembly = new byte[stream.Length];
                stream.Read(assembly, 0, assembly.Length);
                return Assembly.Load(assembly);
            }
        }

        public static void Main(string[] args)
        {
            // Register resolve handler to load embedded assemblies.
            AppDomain.CurrentDomain.AssemblyResolve += ResolveEventHandler;

            if (TryInstallAgent() && TryInstallSysprep())
            {
                TryWriteRegistry();
            }
        }

        private static bool TryInstallAgent()
        {
            Logger.Info("Installing GCE Agent (version {0}).", ReleaseVersion);

            try
            {
                // After version 3.1.0.0, we switched the service name and
                // display name for the agent. For back compatibility, we need
                // check both service name and display name here.
                if (ServiceController.GetServices().Any(x =>
                    x.ServiceName.Equals(ServiceName, StringComparison.InvariantCultureIgnoreCase)
                    || x.DisplayName.Equals(ServiceName, StringComparison.InvariantCultureIgnoreCase)))
                {
                    InstallerUtils.InstallBinaries(ReleaseVersion, AgentBinaries, AgentPath, ServiceName);
                }
                else
                {
                    InstallerUtils.InstallBinaries(ReleaseVersion, AgentBinaries, AgentPath);
                    InstallerUtils.RegisterService(
                        string.Format(@"{0}\{1}", AgentPath, AgentBinaries[0]),
                        ServiceName,
                        ServiceDisplayName);

                    using (ServiceController serviceController = new ServiceController(ServiceName))
                    {
                        serviceController.Start();
                        serviceController.WaitForStatus(ServiceControllerStatus.Running);
                    }
                }
            }
            catch (Exception e)
            {
                Logger.Error(
                    "Failed to install GCE Agent (version {0}). Exception: {1}.",
                    ReleaseVersion,
                    e.ToString());
                return false;
            }

            Logger.Info("GCE Agent (version {0}) installation completed.", ReleaseVersion);
            return true;
        }

        private static bool TryInstallSysprep()
        {
            InstallerUtils.GetSources(ReleaseVersion, ComputeEnginePath);

            string sourcePath = Path.Combine(ComputeEnginePath, InstallerUtils.SourcePath);
            string sysprepSource = Path.Combine(
                sourcePath,
                string.Format(@"compute-image-windows-{0}", ReleaseVersion),
                "gce",
                SysprepDirectory);
            string destination = Path.Combine(ComputeEnginePath, SysprepDirectory);
            string[] sysprepFiles = Directory.GetFiles(sysprepSource).Select(Path.GetFileName).ToArray();

            try
            {
                InstallerUtils.ReplaceFiles(
                    sysprepFiles,
                    sysprepSource,
                    destination,
                    suffix: string.Empty);
            }
            catch (Exception e)
            {
                Logger.Error(
                    "Failed to install Sysprep (version {0}). Exception: {1}.",
                    ReleaseVersion,
                    e.ToString());
                InstallerUtils.Rollback(sysprepFiles, destination);
                return false;
            }

            InstallerUtils.CleanUp(sysprepFiles, destination);
            Directory.Delete(sourcePath, recursive: true);
            return true;
        }

        private static void TryWriteRegistry()
        {
            try
            {
                InstallerUtils.WriteUpdateStatsKey(ApplicationId);
                InstallerUtils.WriteUpdateKey(ApplicationId, ReleaseVersion, ApplicationName);
            }
            catch (Exception e)
            {
                // This branch should never happen when the installer is
                // executed by Omaha client.
                // However, if a user run the installer manually and does not
                // have access to HKLM, this step will fail.
                Logger.Error("Failed to write registry. Exception: {0}.", e.ToString());
            }
        }
    }
}
