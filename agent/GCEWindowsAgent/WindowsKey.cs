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
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using Google.ComputeEngine.Common;

namespace Google.ComputeEngine.Agent
{
    /// <summary>
    /// The JSON object format in windows-keys.
    /// </summary>
    [DataContract]
    internal sealed class WindowsKeyJson
    {
        [DataMember(Name = "email")]
        internal string Email { get; set; }

        [DataMember(Name = "expireOn")]
        internal string ExpireOn { get; set; }

        [DataMember(Name = "exponent")]
        internal string Exponent { get; set; }

        [DataMember(Name = "modulus")]
        internal string Modulus { get; set; }

        [DataMember(Name = "userName")]
        internal string UserName { get; set; }
    }

    /// <summary>
    /// The WindowsKey object
    /// </summary>
    public class WindowsKey
    {
        private string Email { get; set; }
        private string ExpireOn { get; set; }

        public string Exponent { get; private set; }
        public string Modulus { get; private set; }
        public string UserName { get; private set; }

        public WindowsKey(string expireOn, string exponent, string modulus, string userName, string email = "")
        {
            this.ExpireOn = expireOn;
            this.Exponent = exponent;
            this.Modulus = modulus;
            this.UserName = userName;
            this.Email = email;
        }

        /// <summary>
        /// Returns whether the key has an expiration timestamp in the past, or
        /// False otherwise.
        /// </summary>
        public bool HasExpired()
        {
            if (string.IsNullOrEmpty(ExpireOn))
            {
                return false;
            }

            try
            {
                DateTime expireOnTime = Convert.ToDateTime(ExpireOn).ToUniversalTime();

                // Return true only if the current date is greater than the
                // expiration time.
                return DateTime.Compare(DateTime.UtcNow, expireOnTime) > 0;
            }
            catch (FormatException)
            {
                Logger.Warning("Expiration timestamp [{0}] could not be parsed. Not expiring key.", ExpireOn);
                return false;
            }
        }

        /// <summary>
        /// We do not support client reuse of a WindowsKey.
        /// We define WindowsKey equality as public key equality.
        /// Public keys do not get reused.
        /// </summary>
        public override bool Equals(object obj)
        {
            if (obj == null || GetType() != obj.GetType())
            {
                return false;
            }
            WindowsKey windowsKey = (WindowsKey)obj;
            return Exponent == windowsKey.Exponent && Modulus == windowsKey.Modulus;
        }

        public override int GetHashCode()
        {
            return Tuple.Create(Modulus.GetHashCode(), Exponent.GetHashCode()).GetHashCode();
        }

        /// <summary>
        /// Converts a WindowsKey into a serialized JSON string.
        /// </summary>
        /// <returns>The serialized JSON object as a string.</returns>
        public override string ToString()
        {
            WindowsKeyJson windowsKeyJson = new WindowsKeyJson
            {
                Email = this.Email,
                ExpireOn = this.ExpireOn,
                Exponent = this.Exponent,
                Modulus = this.Modulus,
                UserName = this.UserName
            };

            DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(WindowsKeyJson));
            using (MemoryStream stream = new MemoryStream())
            {
                serializer.WriteObject(stream, windowsKeyJson);
                stream.Position = 0;
                using (StreamReader reader = new StreamReader(stream))
                {
                    return reader.ReadToEnd();
                }
            }
        }

        /// <summary>
        /// Deserializes a JSON string into a WindowsKey.
        /// This uses a Google specific JSON object containing the
        /// following properties.
        ///
        /// email: the email of the account creator.
        /// expireOn: the date and time in UTC we should stop accepting the key.
        /// exponent: the exponent for encryption.
        /// modulus: a 2048 bit RSA public key modulus.
        /// userName: the name of the user account.
        ///
        /// This format is still subject to change.
        /// Reliance on it in any way is at your own risk.
        /// </summary>
        /// <param name="windowsKey">The serialized WindowsKey.</param>
        /// <returns>
        /// A WindowsKey object or null if deserialization fails.
        /// </returns>
        public static WindowsKey DeserializeWindowsKey(string windowsKey)
        {
            DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(WindowsKeyJson));
            using (MemoryStream stream = new MemoryStream(Encoding.UTF8.GetBytes(windowsKey)))
            {
                try
                {
                    WindowsKeyJson windowsKeyJson = (WindowsKeyJson)serializer.ReadObject(stream);
                    string expireOn = windowsKeyJson.ExpireOn;
                    string exponent = windowsKeyJson.Exponent;
                    string modulus = windowsKeyJson.Modulus;
                    string userName = windowsKeyJson.UserName;

                    return new WindowsKey(expireOn: expireOn, exponent: exponent, modulus: modulus, userName: userName);
                }
                catch (Exception)
                {
                    Logger.Warning("Windows key [{0}] could not be deserialized.", windowsKey);
                    return null;
                }
            }
        }
    }
}
