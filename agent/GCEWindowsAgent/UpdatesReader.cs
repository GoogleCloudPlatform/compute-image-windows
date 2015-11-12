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

using System.Collections.Generic;
using System.Linq;
using Google.ComputeEngine.Common;

namespace Google.ComputeEngine.Agent
{
    /// <summary>
    /// Reads and parses update configuration settings from GCE's
    /// metadata service.
    /// </summary>
    public sealed class UpdatesReader : IAgentReader<Dictionary<string, bool>>
    {
        public Dictionary<string, bool> GetMetadata(MetadataJson metadata)
        {
            if (metadata == null || metadata.Instance == null || metadata.Instance.Attributes == null)
            {
                return null;
            }

            Dictionary<string, bool> updatesConfigs = new Dictionary<string, bool>
            {
                { AttributeKeys.DisableAgentUpdates, metadata.Instance.Attributes.DisableAgentUpdate },
            };

            return updatesConfigs;
        }

        public bool CompareMetadata(Dictionary<string, bool> oldMetadata, Dictionary<string, bool> newMetadata)
        {
            if (oldMetadata == null || newMetadata == null)
            {
                return oldMetadata == null && newMetadata == null;
            }

            // Checks all keys in old metadata exist in the new metadata and the
            // associated values are the same
            return (oldMetadata.Count == newMetadata.Count) &&
                oldMetadata.Keys.All(key => newMetadata.ContainsKey(key) && oldMetadata[key] == newMetadata[key]);
        }

        public bool IsEnabled(MetadataJson metadata)
        {
            // Disabling the updates component from the metadata server is not
            // supported. This should always return true.
            return true;
        }
    }
}
