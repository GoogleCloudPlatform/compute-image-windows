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
using System.IO;
using System.Linq;
using System.Reflection;

namespace GCEAgentInstaller
{
  public class Installer
  {
    private const string AGENT_PATH = @"C:\Program Files\Google\Compute Engine\agent";
    private const string SERVICE_NAME = @"GCEAgent";
    private const string APPLICATION_NAME = @"GCE Windows Agent";

    /// <summary>
    /// Application ID used by the Omaha service.
    /// </summary>
    private static readonly Guid applicationID = new Guid("3FCD4520-3859-4183-866E-C54153A286EB");

    /// <summary>
    /// Current version of the GCE Windows agent.
    /// </summary>
    private static readonly Version releaseVersion = Assembly.GetExecutingAssembly().GetName().Version;

    /// <summary>
    /// GCE Agent executables and dynamic libraries.
    /// </summary>
    private static readonly string[] agentBinaries = new string[]
    {
      "GCEWindowsAgent.exe",
      "GCEMetadataScripts.exe"
    };

    private static Assembly ResolveEventHandler(Object sender, ResolveEventArgs args)
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
      Install();
    }

    private static void Install()
    {
      InstallerUtils.InstallBinaries(releaseVersion, agentBinaries, AGENT_PATH, SERVICE_NAME);
      InstallerUtils.WriteUpdateKey(applicationID, releaseVersion, APPLICATION_NAME);
      InstallerUtils.WriteUpdateStatsKey(applicationID);
    }
  }
}
