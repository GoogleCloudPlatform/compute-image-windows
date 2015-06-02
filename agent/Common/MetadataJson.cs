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

namespace Common
{
  /// <summary>
  /// These classes define the JSON structure of the metadata server contents.
  /// Use the MetadataJson class to deserialize the JSON string returned
  /// by the metadata server.
  /// </summary>
  [DataContract]
  public class MetadataJson
  {
    [DataMember(Name = "instance")]
    public InstanceJson Instance { get; set; }

    [DataMember(Name = "project")]
    public ProjectJson Project { get; set; }
  }

  [DataContract]
  public class InstanceJson
  {
    [DataMember(Name = "attributes")]
    public AttributesJson Attributes { get; set; }

    [DataMember(Name = "networkInterfaces")]
    public NetworkInterfacesJson[] NetworkInterfaces { get; set; }
  }

  [DataContract]
  public class NetworkInterfacesJson
  {
    [DataMember(Name = "forwardedIps")]
    public string[] ForwardedIps { get; set; }
  }

  [DataContract]
  public class ProjectJson
  {
    [DataMember(Name = "attributes")]
    public AttributesJson Attributes { get; set; }
  }

  [DataContract]
  public class AttributesJson
  {
    [DataMember(Name = "windows-keys")]
    public string WindowsKeys { get; set; }

    [DataMember(Name = "windows-startup-script-ps1")]
    public string WindowsStartupScriptPs1 { get; set; }

    [DataMember(Name = "windows-startup-script-cmd")]
    public string WindowsStartupScriptCmd { get; set; }

    [DataMember(Name = "windows-startup-script-bat")]
    public string WindowsStartupScriptBat { get; set; }

    [DataMember(Name = "windows-startup-script-url")]
    public string WindowsStartupScriptUrl { get; set; }

    [DataMember(Name = "windows-shutdown-script-ps1")]
    public string WindowsShutdownScriptPs1 { get; set; }

    [DataMember(Name = "windows-shutdown-script-cmd")]
    public string WindowsShutdownScriptCmd { get; set; }

    [DataMember(Name = "windows-shutdown-script-bat")]
    public string WindowsShutdownScriptBat { get; set; }

    [DataMember(Name = "windows-shutdown-script-url")]
    public string WindowsShutdownScriptUrl { get; set; }

    [DataMember(Name = "sysprep-oobe-script-ps1")]
    public string SysprepOobeScriptPs1 { get; set; }

    [DataMember(Name = "sysprep-oobe-script-cmd")]
    public string SysprepOobeScriptCmd { get; set; }

    [DataMember(Name = "sysprep-oobe-script-bat")]
    public string SysprepOobeScriptBat { get; set; }

    [DataMember(Name = "sysprep-specialize-script-ps1")]
    public string SysprepSpecializeScriptPs1 { get; set; }

    [DataMember(Name = "sysprep-specialize-script-cmd")]
    public string SysprepSpecializeScriptCmd { get; set; }

    [DataMember(Name = "sysprep-specialize-script-bat")]
    public string SysprepSpecializeScriptBat { get; set; }
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
}
