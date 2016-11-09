using System.Collections.Generic;
using System.Linq;
using Google.ComputeEngine.Common;
using Microsoft.Win32;
using Xunit;

namespace Google.ComputeEngine.Agent.Test
{
    public class RegistryWriterTest
    {
        private const string RegistryKeyPath = @"SOFTWARE\Google\ComputeEngine";

        private RegistryWriter GetRegistryWriter()
        {
            Registry.LocalMachine.DeleteSubKeyTree(RegistryKeyPath, false);
            return new RegistryWriter(RegistryKeyPath);
        }

        private RegistryKey GetRegistryKey()
        {
            return Registry.LocalMachine.OpenSubKey(RegistryKeyPath);
        }

        private void RegistryKeysCompareTest(List<string> expected, RegistryWriter registryWriter, string registryKey)
        {
            List<string> actual = registryWriter.GetMultiStringValue(registryKey);
            Assert.Equal<List<string>>(expected: expected, actual: actual);
        }

        /// <summary>
        /// Given a list of integers to remove from the registry,
        /// a list of integers expected to be in the registry before
        /// removal, and the RegistryWriter object.
        ///
        /// Checks that the registry matches the original registry values
        /// without the removed elements.
        /// </summary>
        /// <param name="remove">A list of integers to remove.</param>
        /// <param name="registryValues">
        /// The registry values before removal.
        /// </param>
        /// <param name="registryWriter">The RegistryWriter object.</param>
        /// <param name="registryKey">Name of registry key.</param>
        private void RemoveRegistryKeysCompareTest(
            List<int> remove,
            List<int> registryValues,
            RegistryWriter registryWriter,
            string registryKey)
        {
            List<string> expected = new List<string>();
            foreach (int value in registryValues)
            {
                if (!remove.Contains(value))
                {
                    expected.Add(value.ToString());
                }
            }
            List<string> values = remove.Select(value => value.ToString()).ToList();
            registryWriter.RemoveMultiStringValues(registryKey, values);
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);
        }

        [Fact]
        public void GetRegistryKeysEmptyTest()
        {
            string registryKey = "GetRegistryKeysEmptyTest";
            RegistryWriter registryWriter = GetRegistryWriter();

            // The registry key should not exist.
            Assert.Null(GetRegistryKey());

            // Get request should return an empty list when registry is empty.
            RegistryKeysCompareTest(
                expected: new List<string>(),
                registryWriter: registryWriter,
                registryKey: registryKey);

            // Get should not mutate the registry state.
            Assert.Null(GetRegistryKey());
        }

        [Fact]
        public void AddRegistryKeyEmptyTest()
        {
            string registryKey = "AddRegistryKeyEmptyTest";
            RegistryWriter registryWriter = GetRegistryWriter();

            // The registry key should not exist.
            Assert.Null(GetRegistryKey());

            // Adding a null value should leave the list of registry keys
            // unchanged.
            registryWriter.AddMultiStringValue(registryKey, registryValue: null);
            RegistryKeysCompareTest(
                expected: new List<string>(),
                registryWriter: registryWriter,
                registryKey: registryKey);

            // Any call to add a registry key should set up the registry key.
            Assert.NotNull(GetRegistryKey());
        }

        [Fact]
        public void AddRegistryKeyTest()
        {
            string registryKey = "AddRegistryKeyTest";
            RegistryWriter registryWriter = GetRegistryWriter();

            // Empty string.
            string registryValueEmpty = string.Empty;

            // Long value.
            string registryValueLong = new string('x', 2048);

            // Special characters.
            string registryValueRandom = @"{}}12345\n\n\nhello\ncd C:\.\n!@#$%^&*()\n-=";

            // Many registry values.
            string[] registryValueList = Enumerable.Range(0, 10000).Select(num => num.ToString()).ToArray();

            List<string> expected = new List<string>();

            registryWriter.AddMultiStringValue(registryKey, registryValueEmpty);
            expected.Add(registryValueEmpty);
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);

            registryWriter.AddMultiStringValue(registryKey, registryValueLong);
            expected.Add(registryValueLong);
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);

            registryWriter.AddMultiStringValue(registryKey, registryValueRandom);
            expected.Add(registryValueRandom);
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);

            foreach (string value in registryValueList)
            {
                registryWriter.AddMultiStringValue(registryKey, value);
                expected.Add(value);
                RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);
            }
        }

        [Fact]
        public void RemoveRegistryKeysEmptyTest()
        {
            string registryKey = "RemoveRegistryKeysEmptyTest";
            RegistryWriter registryWriter = GetRegistryWriter();
            List<string> expected = new List<string>();

            // The registry key should not exist.
            Assert.Null(GetRegistryKey());

            // Adding a null value should leave the list of registry keys
            // unchanged.
            registryWriter.RemoveMultiStringValues(registryKey, null);
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);

            // Calling remove should not create a registry key that doesn't
            // already exist.
            Assert.Null(GetRegistryKey());

            string testValue = "Test value.";
            registryWriter.AddMultiStringValue(registryKey, testValue);
            expected.Add(testValue);
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);

            // Removing null should not modify the list.
            registryWriter.RemoveMultiStringValues(registryKey, null);
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);

            // Removing the empty list should not modify the list.
            registryWriter.RemoveMultiStringValues(registryKey, new List<string>());
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);

            // Removing the empty list containing null should not modify the
            // list.
            registryWriter.RemoveMultiStringValues(registryKey, new List<string> { null });
            RegistryKeysCompareTest(expected: expected, registryWriter: registryWriter, registryKey: registryKey);
        }

        [Fact]
        public void RemoveRegistryKeysTest()
        {
            string registryKey = "RemoveRegistryKeysTest";
            RegistryWriter registryWriter = GetRegistryWriter();

            // List of registry keys to test removal on.
            List<int> registryValues = Enumerable.Range(0, 100).ToList();

            // List of registry keys to remove.
            List<int> registryRemoveList = new List<int>();

            foreach (int value in registryValues)
            {
                registryWriter.AddMultiStringValue(registryKey, value.ToString());
            }

            RemoveRegistryKeysCompareTest(
                remove: registryRemoveList,
                registryValues: registryValues,
                registryWriter: registryWriter,
                registryKey: registryKey);

            // Try removing the first element.
            RemoveRegistryKeysCompareTest(
                remove: new List<int> { 1 },
                registryValues: registryValues,
                registryWriter: registryWriter,
                registryKey: registryKey);

            // Remove all elements less than 10.
            RemoveRegistryKeysCompareTest(
                remove: Enumerable.Range(0, 10).ToList(),
                registryValues: registryValues,
                registryWriter: registryWriter,
                registryKey: registryKey);

            // Remove some elements that do not exist: [0, 50).
            RemoveRegistryKeysCompareTest(
                remove: Enumerable.Range(0, 50).ToList(),
                registryValues: registryValues,
                registryWriter: registryWriter,
                registryKey: registryKey);

            registryValues = Enumerable.Range(50, 50).ToList();

            // Remove only elements that do not exist: [0, 25).
            RemoveRegistryKeysCompareTest(
                remove: Enumerable.Range(0, 25).ToList(),
                registryValues: registryValues,
                registryWriter: registryWriter,
                registryKey: registryKey);

            // Remove a superset of the elements that exist: [50, 150).
            registryRemoveList = Enumerable.Range(0, 50).ToList();
            RemoveRegistryKeysCompareTest(
                remove: Enumerable.Range(50, 100).ToList(),
                registryValues: registryValues,
                registryWriter: registryWriter,
                registryKey: registryKey);

            // Check there are no registry keys left.
            RegistryKeysCompareTest(
                expected: new List<string>(),
                registryWriter: registryWriter,
                registryKey: registryKey);
        }

        [Fact]
        public void RegistryKeysConcurrentTest()
        {
            string registryKeyFoo = "RegistryKeysConcurrentTestFoo";
            string registryKeyBar = "RegistryKeysConcurrentTestBar";
            RegistryWriter writerFoo = GetRegistryWriter();
            RegistryWriter writerBar = new RegistryWriter(RegistryKeyPath);

            // List of Foo's  registry keys to test removal on: [0, 100).
            List<int> registryValuesFoo = Enumerable.Range(0, 100).ToList();

            // List of Bar's registry keys to test removal on: [50, 150).
            List<int> registryValuesBar = Enumerable.Range(50, 100).ToList();

            foreach (int value in registryValuesFoo)
            {
                writerFoo.AddMultiStringValue(registryKeyFoo, value.ToString());
            }

            foreach (int value in registryValuesBar)
            {
                writerBar.AddMultiStringValue(registryKeyBar, value.ToString());
            }

            // Remove elements from Foo that also exist in Bar: [90, 100).
            RemoveRegistryKeysCompareTest(
                remove: Enumerable.Range(90, 10).ToList(),
                registryValues: registryValuesFoo,
                registryWriter: writerFoo,
                registryKey: registryKeyFoo);

            // Remove elements from Bar that also exist in Foo: [50, 60).
            RemoveRegistryKeysCompareTest(
                remove: Enumerable.Range(50, 10).ToList(),
                registryValues: registryValuesBar,
                registryWriter: writerBar,
                registryKey: registryKeyBar);

            // Test that Foo and Bar contain the appropriate elements.
            RegistryKeysCompareTest(
                expected: Enumerable.Range(0, 90).Select(value => value.ToString()).ToList(),
                registryWriter: writerFoo,
                registryKey: registryKeyFoo);

            RegistryKeysCompareTest(
                expected: Enumerable.Range(60, 90).Select(value => value.ToString()).ToList(),
                registryWriter: writerBar,
                registryKey: registryKeyBar);
        }
    }
}