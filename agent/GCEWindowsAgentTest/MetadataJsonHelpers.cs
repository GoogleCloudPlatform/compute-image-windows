using Google.ComputeEngine.Common;
using System.Collections.Generic;
using System.Net;
using System.Net.NetworkInformation;

namespace Google.ComputeEngine.Agent.Test
{
    public class MetadataJsonHelpers
    {
        private MetadataJsonHelpers() { }

        public static MetadataJson GetMetadataJson(
            InstanceJson instance = null,
            ProjectJson project = null)
        {
            MetadataJson metadataJson = new MetadataJson
            {
                Instance = instance ?? GetInstanceMetadataJson(),
                Project = project ?? GetProjectMetadataJson()
            };
            return metadataJson;
        }

        public static InstanceJson GetInstanceMetadataJson(
            AttributesJson attributes = null,
            NetworkInterfacesJson[] networkInterfaces = null)
        {
            InstanceJson instanceJson = new InstanceJson
            {
                Attributes = attributes ?? GetAttributesJson(),
                NetworkInterfaces = networkInterfaces ?? new NetworkInterfacesJson[] { GetNetworkInterfacesJson() }
            };
            return instanceJson;
        }

        public static NetworkInterfacesJson GetNetworkInterfacesJson(string inputMAC = null, string[] inputIPs = null)
        {
            NetworkInterfacesJson networkInterfaces = new NetworkInterfacesJson();
                networkInterfaces.MAC = inputMAC ?? "00 - 11 - 22 - 33 - 44 - 55";
                networkInterfaces.ForwardedIps = inputIPs ?? new string[] { };
            return networkInterfaces;
        }

        public static ProjectJson GetProjectMetadataJson(AttributesJson attributes = null)
        {
            ProjectJson projectJson = new ProjectJson { Attributes = attributes ?? GetAttributesJson() };
            return projectJson;
        }

        public static AttributesJson GetAttributesJson(
            string windowsKeys = null,
            bool disableAddressManager = false,
            bool disableAccountsManager = false,
            bool disableAgentUpdate = false)
        {
            AttributesJson attributes = new AttributesJson
            {
                WindowsKeys = windowsKeys,
                DisableAddressManager = disableAddressManager,
                DisableAccountManager = disableAccountsManager,
                DisableAgentUpdate = disableAgentUpdate
            };
            return attributes;
        }
    }
}