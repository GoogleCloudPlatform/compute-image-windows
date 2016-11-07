using System;
using System.Collections.Generic;
using Google.ComputeEngine.Common;
using Xunit;

namespace Google.ComputeEngine.Agent.Test
{
    public class AccountsReaderTest
    {
        private const string Email = "test@google.com";
        private const string Exponent = "test+exponent";
        private const string Modulus = "test+modulus";
        private const string Username = "testUserName";
        private static readonly AccountsReader Reader = new AccountsReader();

        /// <summary>
        /// Creates a date time string in the windows key format.
        /// </summary>
        /// <param name="offset">Hours before key expires.</param>
        /// <returns>The date time string for the windows key.</returns>
        private static string GetDateTime(int offset)
        {
            return DateTime.UtcNow.AddHours(offset).ToString("yyyy-MM-ddTHH:mm:sszzz");
        }

        private static WindowsKey GetWindowsKey(
            string expireOn = "",
            string exponent = Exponent,
            string modulus = Modulus,
            string userName = Username,
            string email = Email)
        {
            return new WindowsKey(
              expireOn: expireOn, exponent: exponent, modulus: modulus, userName: userName, email: email);
        }

        private static MetadataJson CreateTestMetadata(string windowsKeys, bool disableAccountManager = false)
        {
            AttributesJson attributes = MetadataJsonHelpers.GetAttributesJson(
                windowsKeys: windowsKeys,
                disableAccountsManager: disableAccountManager);
            InstanceJson instance = MetadataJsonHelpers.GetInstanceMetadataJson(attributes: attributes);
            return MetadataJsonHelpers.GetMetadataJson(instance: instance);
        }

        /// <summary>
        /// Compares the response of GetMetadata with the expected response.
        /// </summary>
        /// <param name="input">The metadata value of windows-keys.</param>
        /// <param name="expected">The expected response of GetMetadata</param>
        private static void GetMetadataTest(string input, List<WindowsKey> expected)
        {
            MetadataJson metadata = CreateTestMetadata(input);
            Assert.Equal<List<WindowsKey>>(expected, Reader.GetMetadata(metadata));
        }

        [Fact]
        public void GetMetadataEmptyTest()
        {
            MetadataJson metadata = MetadataJsonHelpers.GetMetadataJson();
            Assert.Equal(new List<WindowsKey>(), Reader.GetMetadata(metadata));

            metadata.Instance = null;
            Assert.Null(Reader.GetMetadata(metadata));

            metadata = null;
            Assert.Null(Reader.GetMetadata(metadata));
        }

        [Fact]
        public void GetMetadataExpirationTest()
        {
            WindowsKey validWindowsKey, invalidWindowsKey;

            // Valid key containing no expiration time.
            validWindowsKey = GetWindowsKey();
            GetMetadataTest(
                input: validWindowsKey.ToString(),
                expected: new List<WindowsKey> { validWindowsKey });

            // Valid key containing a expiration time that can't be parsed.
            validWindowsKey = GetWindowsKey(expireOn: "invalid");
            GetMetadataTest(
                input: validWindowsKey.ToString(),
                expected: new List<WindowsKey> { validWindowsKey });

            // Valid key expiring in one hour.
            validWindowsKey = GetWindowsKey(expireOn: GetDateTime(1));
            GetMetadataTest(
                input: validWindowsKey.ToString(),
                expected: new List<WindowsKey> { validWindowsKey });

            // Invalid key that expired an hour earlier.
            invalidWindowsKey = GetWindowsKey(expireOn: GetDateTime(-1));
            GetMetadataTest(
                input: invalidWindowsKey.ToString(),
                expected: new List<WindowsKey>());

            // Both, the valid and invalid keys.
            GetMetadataTest(
                input: string.Join("\n", new List<WindowsKey> { invalidWindowsKey, validWindowsKey }),
                expected: new List<WindowsKey> { validWindowsKey });
        }

        [Fact]
        public void GetMetadataMissingKeyTest()
        {
            // Missing exponent.
            GetMetadataTest(
                input: GetWindowsKey(exponent: string.Empty).ToString(),
                expected: new List<WindowsKey>());

            // Missing modulus.
            GetMetadataTest(
                input: GetWindowsKey(modulus: string.Empty).ToString(),
                expected: new List<WindowsKey>());

            // Missing userName.
            GetMetadataTest(
                input: GetWindowsKey(userName: string.Empty).ToString(),
                expected: new List<WindowsKey>());
        }

        [Fact]
        public void GetMetadataRandomStringsTest()
        {
            WindowsKey validWindowsKey = GetWindowsKey();

            // Check we ignore extraneous new lines and non-windows-key strings.
            GetMetadataTest(
                input: string.Format("{{}}\n\n\nhello\n{0}\n!@#$%^&*()\n\n\n{0}", validWindowsKey.ToString()),
                expected: new List<WindowsKey> { validWindowsKey, validWindowsKey });

            // Additional fields in the key should be ignored.
            string windowsKeyJson =
                "{\"userName\":\"test\",\"exponent\":\"test\",\"modulus\":\"test\",\"extra\":\"test\"}";
            validWindowsKey = GetWindowsKey(userName: "test", exponent: "test", modulus: "test", email: string.Empty);
            GetMetadataTest(
                input: windowsKeyJson,
                expected: new List<WindowsKey> { validWindowsKey });

            // Invalid argument types should not be parsed as a windows key.
            windowsKeyJson = "{" +
                "\"userName\":\"test\"," +
                "\"exponent\":\"test\"," +
                "\"modulus\":\"test\"," +
                "\"extra\":\"test\"," +
                "\"info\":{{\"json\":\"input\"}}" +
                "}";
            validWindowsKey = GetWindowsKey(userName: "test", exponent: "test", modulus: "test", email: string.Empty);
            GetMetadataTest(
                input: windowsKeyJson,
                expected: new List<WindowsKey> { validWindowsKey });
        }

        [Fact]
        public void CompareMetadataEmptyTest()
        {
            List<WindowsKey> windowsKeys = new List<WindowsKey>();
            Assert.True(Reader.CompareMetadata(null, null));
            Assert.True(Reader.CompareMetadata(windowsKeys, windowsKeys));
            Assert.False(Reader.CompareMetadata(null, windowsKeys));
            Assert.False(Reader.CompareMetadata(windowsKeys, null));
        }

        /// <summary>
        /// Lists of WindowsKeys that should be considered equal.
        /// WindowsKeys should only be compared by their modulus and exponent.
        /// </summary>
        [Fact]
        public void CompareMetadataEqualityTest()
        {
            List<WindowsKey> windowsKeys = new List<WindowsKey>
            {
                GetWindowsKey(expireOn: GetDateTime(1), userName: "one", email: "one"),
                GetWindowsKey(expireOn: GetDateTime(2), userName: "two", email: "two")
            };
            Assert.True(Reader.CompareMetadata(windowsKeys, new List<WindowsKey> { GetWindowsKey() }));

            windowsKeys.Add(GetWindowsKey(expireOn: GetDateTime(3)));
            windowsKeys.Add(GetWindowsKey(userName: "four"));
            windowsKeys.Add(GetWindowsKey(email: "five@google.com"));
            Assert.True(Reader.CompareMetadata(windowsKeys, new List<WindowsKey> { GetWindowsKey() }));

            // Expiration should not impact the comparison.
            List<WindowsKey> windowsKeysModified = new List<WindowsKey>
            {
                GetWindowsKey(expireOn: GetDateTime(-1), exponent: "exp")
            };
            Assert.False(Reader.CompareMetadata(windowsKeys, windowsKeysModified));

            windowsKeysModified.Clear();
            windowsKeysModified.Add(GetWindowsKey(expireOn: GetDateTime(-1), modulus: "mod"));
            Assert.False(Reader.CompareMetadata(windowsKeys, windowsKeysModified));
        }

        [Fact]
        public void CompareMetadataPermutationTest()
        {
            List<WindowsKey> windowsKeys = new List<WindowsKey>
            {
                GetWindowsKey(userName: "one", modulus: "one", exponent: "one"),
                GetWindowsKey(userName: "two", modulus: "two", exponent: "two"),
                GetWindowsKey(userName: "three", modulus: "three", exponent: "three"),
                GetWindowsKey(userName: "four", modulus: "four", exponent: "four")
            };

            List<WindowsKey> windowsKeysPermutation = new List<WindowsKey>
            {
                GetWindowsKey(userName: "two", modulus: "two", exponent: "two"),
                GetWindowsKey(userName: "one", modulus: "one", exponent: "one"),
                GetWindowsKey(userName: "four", modulus: "four", exponent: "four"),
                GetWindowsKey(userName: "three", modulus: "three", exponent: "three")
            };

            Assert.True(Reader.CompareMetadata(windowsKeys, windowsKeysPermutation));
        }

        [Fact]
        public void ComponentIsEnabledTest()
        {
            MetadataJson metadata = CreateTestMetadata(windowsKeys: null, disableAccountManager: false);
            Assert.True(Reader.IsEnabled(metadata));

            metadata = CreateTestMetadata(windowsKeys: null, disableAccountManager: true);
            Assert.False(Reader.IsEnabled(metadata));
        }
    }
}