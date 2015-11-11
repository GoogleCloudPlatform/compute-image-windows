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

using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

namespace Google.ComputeEngine.Common
{
    /// <summary>
    /// These classes define the JSON structure of the metadata server contents.
    /// Use the MetadataJson class to deserialize the JSON string returned
    /// by the metadata server.
    /// </summary>
    [DataContract]
    public sealed class MetadataJson
    {
        [DataMember(Name = "instance")]
        public InstanceJson Instance { get; set; }

        [DataMember(Name = "project")]
        public ProjectJson Project { get; set; }
    }

    [DataContract]
    public sealed class InstanceJson
    {
        [DataMember(Name = "attributes")]
        public AttributesJson Attributes { get; set; }

        [DataMember(Name = "networkInterfaces")]
        public NetworkInterfacesJson[] NetworkInterfaces { get; set; }
    }

    [DataContract]
    public sealed class NetworkInterfacesJson
    {
        [DataMember(Name = "forwardedIps")]
        public string[] ForwardedIps { get; set; }
    }

    [DataContract]
    public sealed class ProjectJson
    {
        [DataMember(Name = "attributes")]
        public AttributesJson Attributes { get; set; }
    }

    [DataContract]
    public sealed class AttributesJson
    {
        #region Windows GCE Agent
        [DataMember(Name = AttributeKeys.WindowsKeys)]
        public string WindowsKeys { get; set; }

        [DataMember(Name = AttributeKeys.DisableAddressManager)]
        public bool DisableAddressManager { get; set; }

        [DataMember(Name = AttributeKeys.DisableAccountManager)]
        public bool DisableAccountManager { get; set; }

        [DataMember(Name = AttributeKeys.DisableAgentUpdates)]
        public bool DisableAgentUpdate { get; set; }
        #endregion

        #region Startup Scripts
        [DataMember(Name = AttributeKeys.WindowsStartupScriptPs1)]
        public string WindowsStartupScriptPs1 { get; set; }

        [DataMember(Name = AttributeKeys.WindowsStartupScriptCmd)]
        public string WindowsStartupScriptCmd { get; set; }

        [DataMember(Name = AttributeKeys.WindowsStartupScriptBat)]
        public string WindowsStartupScriptBat { get; set; }

        [DataMember(Name = AttributeKeys.WindowsStartupScriptUrl)]
        public string WindowsStartupScriptUrl { get; set; }
        #endregion

        #region Shutdown Scripts
        [DataMember(Name = AttributeKeys.WindowsShutdownScriptPs1)]
        public string WindowsShutdownScriptPs1 { get; set; }

        [DataMember(Name = AttributeKeys.WindowsShutdownScriptCmd)]
        public string WindowsShutdownScriptCmd { get; set; }

        [DataMember(Name = AttributeKeys.WindowsShutdownScriptBat)]
        public string WindowsShutdownScriptBat { get; set; }

        [DataMember(Name = AttributeKeys.WindowsShutdownScriptUrl)]
        public string WindowsShutdownScriptUrl { get; set; }
        #endregion

        #region Sysprep Startup Scripts
        [DataMember(Name = AttributeKeys.SysprepOobeScriptPs1)]
        public string SysprepOobeScriptPs1 { get; set; }

        [DataMember(Name = AttributeKeys.SysprepOobeScriptCmd)]
        public string SysprepOobeScriptCmd { get; set; }

        [DataMember(Name = AttributeKeys.SysprepOobeScriptBat)]
        public string SysprepOobeScriptBat { get; set; }

        [DataMember(Name = AttributeKeys.SysprepSpecializeScriptPs1)]
        public string SysprepSpecializeScriptPs1 { get; set; }

        [DataMember(Name = AttributeKeys.SysprepSpecializeScriptCmd)]
        public string SysprepSpecializeScriptCmd { get; set; }

        [DataMember(Name = AttributeKeys.SysprepSpecializeScriptBat)]
        public string SysprepSpecializeScriptBat { get; set; }
        #endregion
    }

    public static class MetadataDeserializer
    {
        /// <summary>
        /// Deserialize a JSON string into an object of type T.
        /// </summary>
        public static T DeserializeMetadata<T>(string metadata)
        {
            DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(T));
            using (MemoryStream stream = new MemoryStream(Encoding.UTF8.GetBytes(metadata)))
            {
                return (T)serializer.ReadObject(stream);
            }
        }
    }

    public static class MetadataSerializer
    {
        /// <summary>
        /// Serialize an object of type T into a JSON string.
        /// </summary>
        public static string SerializeMetadata<T>(T metadata)
        {
            DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(T));
            using (MemoryStream stream = new MemoryStream())
            {
                serializer.WriteObject(stream, metadata);
                stream.Position = 0;
                using (StreamReader reader = new StreamReader(stream))
                {
                    return reader.ReadToEnd();
                }
            }
        }
    }

    public static class AttributeKeys
    {
        public const string DisableAccountManager = "disable-account-manager";
        public const string DisableAddressManager = "disable-address-manager";
        public const string DisableAgentUpdates = "disable-agent-updates";
        public const string SysprepOobeScriptBat = "sysprep-oobe-script-bat";
        public const string SysprepOobeScriptCmd = "sysprep-oobe-script-cmd";
        public const string SysprepOobeScriptPs1 = "sysprep-oobe-script-ps1";
        public const string SysprepSpecializeScriptBat = "sysprep-specialize-script-bat";
        public const string SysprepSpecializeScriptCmd = "sysprep-specialize-script-cmd";
        public const string SysprepSpecializeScriptPs1 = "sysprep-specialize-script-ps1";
        public const string WindowsKeys = "windows-keys";
        public const string WindowsShutdownScriptBat = "windows-shutdown-script-bat";
        public const string WindowsShutdownScriptCmd = "windows-shutdown-script-cmd";
        public const string WindowsShutdownScriptPs1 = "windows-shutdown-script-ps1";
        public const string WindowsShutdownScriptUrl = "windows-shutdown-script-url";
        public const string WindowsStartupScriptPs1 = "windows-startup-script-ps1";
        public const string WindowsStartupScriptCmd = "windows-startup-script-cmd";
        public const string WindowsStartupScriptBat = "windows-startup-script-bat";
        public const string WindowsStartupScriptUrl = "windows-startup-script-url";
    }
}
