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
using System.Reflection;
using System.ServiceProcess;

namespace GCEAgent
{
  /// <summary>
  /// Service daemon for GCE hosted Windows VMs.
  /// </summary>
  public class GCEService : ServiceBase
  {
    private MetadataService metadataService;

    public GCEService()
    {
      metadataService = new MetadataService();
    }

    protected override void OnStart(string[] args)
    {
      string version = "unknown";
      try
      {
        version = Assembly.GetExecutingAssembly().GetName().Version.ToString();
      }
      catch (Exception e)
      {
        Logger.Warning("Exception caught reading version number. {0}", e);
      }
      finally
      {
        string doc_url = "https://cloud.google.com/compute/docs/operating-systems/windows#understand_auth";
        string[] startup_message = { string.Format("GCE Agent started (version {0}).", version),
                                     new string('-', 80),
                                     "This instance is using a new secure authentication scheme.",
                                     "Please verify you are running gcloud version 0.9.58 or newer.",
                                     "",
                                     "For more information, refer to:",
                                     doc_url,
                                     new string('-', 80) };
        Logger.Info(string.Join("\n", startup_message));
        metadataService.OnStart();
      }
    }

    protected override void OnStop()
    {
      metadataService.OnStop();
      Logger.Info("GCE Agent stopped.");
    }

    static void Main(string[] args)
    {
      ServiceBase.Run(new GCEService());
    }
  }
}
