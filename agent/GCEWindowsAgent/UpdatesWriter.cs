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
using Google.ComputeEngine.Common;

namespace Google.ComputeEngine.Agent
{
    /// <summary>
    /// Set automatic update configurations on instance.
    /// </summary>
    public sealed class UpdatesWriter : IAgentWriter<Dictionary<string, bool>>
    {
        private const string OmahaClientState = @"SOFTWARE\Google\Update\ClientState";
        private const string AdditionalParameterKey = "ap";
        private static readonly Guid AgentApplicationID = new Guid("3FCD4520-3859-4183-866E-C54153A286EB");

        private static string GetRegistryValue(bool disabled)
        {
            return disabled ? "disabled" : "enabled";
        }

        public void SetMetadata(Dictionary<string, bool> metadata)
        {
            if (metadata == null)
            {
                return;
            }

            // Set a registry value under ClientState subkey.
            // App ID is in format {00000000-0000-0000-0000-000000000000}.
            RegistryWriter registryWriter = new RegistryWriter(OmahaClientState);
            registryWriter.SetStringValue(
                AgentApplicationID.ToString("B").ToUpper(),
                AdditionalParameterKey,
                GetRegistryValue(metadata[AttributeKeys.DisableAgentUpdates]));
        }
    }
}
