using System.Collections.Generic;
using System.Net;
using Google.ComputeEngine.Common;
using Xunit;
using System.Net.NetworkInformation;
using System.Linq;

namespace Google.ComputeEngine.Agent.Test
{
    public class AddressReaderTest
    {
        private static readonly AddressReader Reader = new AddressReader();

        private static void GetMetadataNetworkInterfacesTest(NetworkInterfacesJson[] input, 
            Dictionary<PhysicalAddress, List<IPAddress>> expected)
        {
            InstanceJson instance = MetadataJsonHelpers.GetInstanceMetadataJson(networkInterfaces: input);
            MetadataJson metadata = MetadataJsonHelpers.GetMetadataJson(instance: instance);
            Assert.Equal<Dictionary<PhysicalAddress, List<IPAddress>>>(expected, Reader.GetMetadata(metadata));
        }

        private static MetadataJson CreateTestMetadata(string[] forwardAddresses, bool disableAddressManager = true)
        {
            AttributesJson attributes = MetadataJsonHelpers.GetAttributesJson(
                disableAddressManager: disableAddressManager);
            InstanceJson instance = MetadataJsonHelpers.GetInstanceMetadataJson(
                attributes,
                new[] { MetadataJsonHelpers.GetNetworkInterfacesJson(inputIPs: forwardAddresses) });
            return MetadataJsonHelpers.GetMetadataJson(instance: instance);
        }

        /// <summary>
        /// Compares the response of GetMetadata with the expected response.
        /// </summary>
        /// <param name="input">The metadata value of forwardedIps.</param>
        /// <param name="expected">The expected response of GetMetadata</param>
        private static void GetMetadataTest(string inputMAC, string[] inputIPs, Dictionary<PhysicalAddress, List<IPAddress>> expected)
        {
            NetworkInterfacesJson networkInterface = MetadataJsonHelpers.GetNetworkInterfacesJson(inputMAC, inputIPs);
            NetworkInterfacesJson[] networkInterfaces = new NetworkInterfacesJson[] { networkInterface };
            GetMetadataNetworkInterfacesTest(networkInterfaces, expected);
        }

        [Fact]
        public void GetMetadataEmptyTest()
        {
            MetadataJson metadata = MetadataJsonHelpers.GetMetadataJson();
            Assert.Equal(new Dictionary<PhysicalAddress, List<IPAddress>>(), Reader.GetMetadata(metadata));

            metadata.Instance = null;
            Assert.Equal(new Dictionary<PhysicalAddress, List<IPAddress>>(), Reader.GetMetadata(metadata));

            metadata = null;
            Assert.Equal(new Dictionary<PhysicalAddress, List<IPAddress>>(), Reader.GetMetadata(metadata));
        }

        [Fact]
        public void GetMetadataInvalidIpTest()
        {
            Dictionary<PhysicalAddress, List<IPAddress>> expected = new Dictionary<PhysicalAddress, List<IPAddress>>
            {
                { PhysicalAddress.Parse("00-11-22-33-44-55"), new List<IPAddress> { }}
            };

            // No IPs provided.
            GetMetadataTest("00-11-22-33-44-55", new string[] { }, expected);

            // Null IPs provided.
            GetMetadataTest("00-11-22-33-44-55", new string[] { null }, expected);

            // Random string given.
            GetMetadataTest("00-11-22-33-44-55", new string[] { "invalid" }, expected);

            // Incorrect number of bytes.
            GetMetadataTest("00-11-22-33-44-55", new string[] { "1.1.1.1.1" }, expected);

            // Invalid byte.
            GetMetadataTest("00-11-22-33-44-55", new string[] { "1111.1.1.1" }, expected);
        }

        [Fact]
        public void GetMetadataRandomIpTest()
        {
            // Basic IP address.
            GetMetadataTest("00-11-22-33-44-55", new string[] { "1.1.1.1" },
                new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { PhysicalAddress.Parse("00-11-22-33-44-55"),
                        new List<IPAddress> { IPAddress.Parse("1.1.1.1") }
                    }
                });

            // Check we ignore non-ip address strings.
            GetMetadataTest("00-11-22-33-44-55",
                new string[] { "{{}}\n\"hello\"\n!@#$%^&*()\n\n", "1111.1.1.1", "1.1.1.1", "hello", "2.2.2.2" },
                new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { PhysicalAddress.Parse("00-11-22-33-44-55"),
                        new List<IPAddress> { IPAddress.Parse("1.1.1.1"), IPAddress.Parse("2.2.2.2") }
                    }
                });

            // Check that we ignore empty and null strings.
            GetMetadataTest("00-11-22-33-44-55",
                new string[] { "1.1.1.1", null, string.Empty, "2.2.2.2" },
                new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { PhysicalAddress.Parse("00-11-22-33-44-55"),
                        new List<IPAddress> { IPAddress.Parse("1.1.1.1"), IPAddress.Parse("2.2.2.2") }
                    }
                });
        }

        [Fact]
        public void GetMetadataNetworkInterfacesTest()
        {
            string[] forwardedIps = new string[] { "1.1.1.1", "2.2.2.2" };

            NetworkInterfacesJson[] networkInterfaces = new NetworkInterfacesJson[]
            {
                MetadataJsonHelpers.GetNetworkInterfacesJson("00-11-22-33-44-55", forwardedIps),
            };
            GetMetadataNetworkInterfacesTest(
                input: networkInterfaces,
                expected: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { PhysicalAddress.Parse("00-11-22-33-44-55"),
                        new List<IPAddress> { IPAddress.Parse("1.1.1.1"), IPAddress.Parse("2.2.2.2") }
                    }
                });
        }

        [Fact]
        public void CompareMetadataEmptyTest()
        {
            Dictionary<PhysicalAddress, List<IPAddress>> forwardedIps = new Dictionary<PhysicalAddress, 
                List<IPAddress>>();
            Assert.True(Reader.CompareMetadata(null, null));
            Assert.True(Reader.CompareMetadata(forwardedIps, forwardedIps));
            Assert.False(Reader.CompareMetadata(null, forwardedIps));
            Assert.False(Reader.CompareMetadata(forwardedIps, null));
        }

        /// <summary>
        /// Basic IP address comparisons testing equality.
        /// </summary>
        [Fact]
        public void CompareMetadataEqualityTest()
        {
            PhysicalAddress MAC = PhysicalAddress.Parse("00-11-22-33-44-55");

            // Two lists of IPs are equal if they contain the same set of unique IPs.
            Assert.True(Reader.CompareMetadata(
                oldMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    {
                        MAC,
                        new List<IPAddress> {
                            IPAddress.Parse("127.127.127.120"),
                            IPAddress.Parse("127.127.127.121"),
                            IPAddress.Parse("127.127.127.122"),
                        }
                    }
                },
                newMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    {
                        MAC,
                        new List<IPAddress> {
                            IPAddress.Parse("127.127.127.122"),
                            IPAddress.Parse("127.127.127.121"),
                            IPAddress.Parse("127.127.127.120"),
                        }
                    }
                }));

            // Simple IP equality.
            Assert.True(Reader.CompareMetadata(
                oldMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("127.127.127.127") } }
                },
                newMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("127.127.127.127") } }
                }));

            // Ensure parsing is done properly.
            Assert.False(Reader.CompareMetadata(
                oldMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("101.1.1.1") } }
                },
                newMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("10.11.1.1") } }
                }));

            Assert.False(Reader.CompareMetadata(
                oldMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { PhysicalAddress.Parse("00-11-22-33-44-AA"),
                        new List<IPAddress> { IPAddress.Parse("101.1.1.1") }
                    }
                },
                newMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("10.1.1.1") } }
                }));

            Assert.False(Reader.CompareMetadata(
                oldMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress>() }
                },
                newMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("10.1.1.1") } }
                }));

            Assert.False(Reader.CompareMetadata(
                oldMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("10.1.1.1") } }
                },
                newMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress>() }
                }));

            Assert.False(Reader.CompareMetadata(
                oldMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("10.1.1.1") } }
                },
                newMetadata: new Dictionary<PhysicalAddress, List<IPAddress>> {
                    { MAC, new List<IPAddress> { IPAddress.Parse("10.1.1.1"), IPAddress.Parse("10.1.1.2") } }
                }));
        }

        [Fact]
        public void CompareMetadataPermutationTest()
        {
            Dictionary<PhysicalAddress, List<IPAddress>> forwardedIpsDict = new Dictionary<PhysicalAddress, 
                List<IPAddress>>
            {
                {
                    PhysicalAddress.Parse("00-11-22-33-44-55"),
                    new List<IPAddress>
                    {
                        IPAddress.Parse("1.1.1.1"),
                        IPAddress.Parse("2.2.2.2"),
                        IPAddress.Parse("3.3.3.3"),
                        IPAddress.Parse("4.4.4.4")
                    }
                }
            };

            Dictionary<PhysicalAddress, List<IPAddress>> forwardedIpsDict2 = new Dictionary<PhysicalAddress, 
                List<IPAddress>>
            {
                {
                    PhysicalAddress.Parse("00-11-22-33-44-55"),
                    new List<IPAddress>
                    {
                        IPAddress.Parse("2.2.2.2"),
                        IPAddress.Parse("1.1.1.1"),
                        IPAddress.Parse("4.4.4.4"),
                        IPAddress.Parse("3.3.3.3")
                    }
                }
            };

            Assert.True(Reader.CompareMetadata(forwardedIpsDict, forwardedIpsDict2));
        }

        [Fact]
        public void ComponentIsEnabledTest()
        {
            MetadataJson metadata = CreateTestMetadata(forwardAddresses: null, disableAddressManager: false);
            Assert.True(Reader.IsEnabled(metadata));

            metadata = CreateTestMetadata(forwardAddresses: null, disableAddressManager: true);
            Assert.False(Reader.IsEnabled(metadata));
        }
    }
}