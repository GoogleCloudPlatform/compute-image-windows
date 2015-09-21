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
using System.Diagnostics;
using System.Runtime.Serialization;
using System.Threading;
using Google.ComputeEngine.Common;

namespace Google.ComputeEngine.Agent
{
    /// <summary>
    /// The JSON object format for agent startup information.
    /// </summary>
    [DataContract]
    internal class GoogleAgentStartupJson
    {
        [DataMember(Name = "ready")]
        internal bool Ready { get; set; }

        [DataMember(Name = "version")]
        internal string OSVersion { get; set; }
    }

    internal class MetadataService
    {
        private AccountsManager accountsManager = new AccountsManager();
        private AddressManager addressManager = new AddressManager();
        private readonly CancellationTokenSource token = new CancellationTokenSource();

        private static void PrintAgentStartupJson()
        {
            GoogleAgentStartupJson agentStartupJson = new GoogleAgentStartupJson
            {
                Ready = true,
                OSVersion = Environment.OSVersion.ToString()
            };

            string serializedAgentStartup = MetadataSerializer
                .SerializeMetadata<GoogleAgentStartupJson>(agentStartupJson);
            Logger.LogWithCom(EventLogEntryType.Information, "COM4", "{0}", serializedAgentStartup);
        }

        public void OnStart()
        {
            // Indicate a Windows instance is running.
            PrintAgentStartupJson();

            // Run the work loop until the service shuts down
            MetadataWatcher.UpdateToken(token);
        }

        public void OnStop()
        {
            token.Cancel();
        }
    }
}
