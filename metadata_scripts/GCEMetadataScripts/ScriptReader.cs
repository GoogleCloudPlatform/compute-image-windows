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
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text.RegularExpressions;
using Google.ComputeEngine.Common;

namespace Google.ComputeEngine.MetadataScripts
{
    /// <summary>
    /// Enables clients to access scripts via GCE's metadata service.
    /// </summary>
    public sealed class ScriptReader
    {
        // Give up after multiple failed attempts.
        private const int RetryLimit = 5;
        private readonly string scriptType;

        public ScriptReader(string scriptType)
        {
            this.scriptType = scriptType;
        }

        /// <summary>
        /// Generate a new file name to store a metadata script.
        /// </summary>
        /// <param name="suffix">
        /// The script type indicating the appropriate file extension.
        /// </param>
        /// <returns>The filename of the file created.</returns>
        private string GetTempFileName(string suffix)
        {
            string scriptTypeString = MetadataScript.GetMetadataTypeString(this.scriptType, suffix);
            string fileName;
            do
            {
                fileName = string.Format("{0}{1}.{2}", Path.GetTempPath(), Guid.NewGuid(), suffix);
            }
            while (File.Exists(fileName));
            return fileName;
        }

        /// <summary>
        /// Download a Google Storage URL using gsutil.
        /// </summary>
        /// <param name="gsurl">
        /// The URL to download.
        /// </param>
        /// <param name="fileName">
        /// The file where we should download the script.
        /// </param>
        /// <returns>
        /// A boolean representing whether the gsutil copy succeeded.
        /// </returns>
        private bool DownloadGSUrl(string gsurl, string fileName)
        {
            Logger.Info("Downloading {0} script from [{1}] using gsutil.", this.scriptType, gsurl);
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = "gsutil.cmd";
            startInfo.Arguments = string.Format("cp \"{0}\" {1}", gsurl, fileName);
            startInfo.UseShellExecute = true;
            startInfo.CreateNoWindow = true;
            try
            {
                using (Process process = Process.Start(startInfo))
                {
                    process.WaitForExit();
                    return process.ExitCode == 0;
                }
            }
            catch (Exception e)
            {
                Logger.Warning(
                    "Could not download {0} script using gsutil. Caught exception: [{1}].",
                    this.scriptType,
                    e.Message);
                return false;
            }
        }

        /// <summary>
        /// Downloads a script from a given URL.
        /// </summary>
        /// <param name="url">The URL to download the script from.</param>
        /// <param name="fileName">The file to store the script.</param>
        /// <returns>A boolean representing if the download succeeded.</returns>
        private bool DownloadUrl(string url, string fileName)
        {
            WebClient client = new WebClient();
            int attempt = 1;
            while (true)
            {
                try
                {
                    client.DownloadFile(url, fileName);
                    Logger.Info("Successfully downloaded {0} script [{1}].", this.scriptType, url);
                    return true;
                }
                catch (WebException e)
                {
                    Logger.Warning(
                        "WebException downloading {0} script: [{1}], status: [{2}].",
                        this.scriptType,
                        e.Message,
                        e.Status);
                    if (attempt++ >= RetryLimit)
                    {
                        Logger.Warning(
                            "Could not download {0} script [{1}].",
                            this.scriptType,
                            url);
                        return false;
                    }
                }
                catch (Exception e)
                {
                    Logger.Warning(
                        "Could not download {0} script [{1}]. Caught exception: [{2}].",
                        this.scriptType,
                        url,
                        e.Message);
                    return false;
                }
            }
        }

        /// <summary>
        /// Determines whether a requested URL is on Google Storage and
        /// downloads it.
        /// </summary>
        /// <param name="url">The URL location of the metadata script.</param>
        /// <param name="fileName">The file to store the script.</param>
        /// <returns>A boolean representing if the download succeeded.</returns>
        private bool DownloadScript(string url, string fileName)
        {
            // Many of the Google Storage URLs are supported below.
            // It is preferred that customers specify their object using
            // its gs://<bucket>/<object> URL.
            string bucket = @"(?<bucket>[a-z0-9][-_.a-z0-9]*)";

            // Accept any non-empty string that doesn't contain a wildcard
            // character.
            // gsutil interprets some characters as wildcards.
            // These characters in object names make it difficult or impossible
            // to perform various wildcard operations using gsutil.
            // For a complete list use "gsutil help naming".
            string obj = @"(?<object>[^\*\?]+)";

            // Check for the preferred Google Storage URL format:
            // gs://<bucket>/<object>
            string gsRegex = string.Format(@"gs://{0}/{1}", bucket, obj);
            if (Regex.IsMatch(url, gsRegex))
            {
                return DownloadGSUrl(url, fileName);
            }

            // Check for the Google Storage URLs:
            // http://<bucket>.storage.googleapis.com/<object>
            // https://<bucket>.storage.googleapis.com/<object>
            gsRegex = string.Format(@"http[s]?://{0}\.storage\.googleapis\.com/{1}", bucket, obj);
            Match match = Regex.Match(url, gsRegex);
            if (match.Groups.Count > 1)
            {
                string gsurl = string.Format(@"gs://{0}/{1}", match.Groups["bucket"], match.Groups["object"]);
                if (DownloadGSUrl(gsurl, fileName))
                {
                    return true;
                }
            }

            // Check for the other possible Google Storage URLs:
            // http://storage.googleapis.com/<bucket>/<object>
            // https://storage.googleapis.com/<bucket>/<object>
            //
            // The following are deprecated but checked:
            // http://commondatastorage.googleapis.com/<bucket>/<object>
            // https://commondatastorage.googleapis.com/<bucket>/<object>
            gsRegex = string.Format(@"http[s]?://(commondata)?storage\.googleapis\.com/{0}/{1}", bucket, obj);
            match = Regex.Match(url, gsRegex);
            if (match.Groups.Count > 1)
            {
                string gsurl = string.Format(@"gs://{0}/{1}", match.Groups["bucket"], match.Groups["object"]);
                if (DownloadGSUrl(gsurl, fileName))
                {
                    return true;
                }
            }

            // Unauthenticated download of the object.
            return DownloadUrl(url, fileName);
        }

        /// <summary>
        /// Downloads the script if a URL is provided.
        /// Saves the metadata script to a new file whose suffix matches the
        /// script type.
        /// </summary>
        /// <param name="suffix">
        /// The file type of the metadata script getting run.
        /// </param>
        /// <param name="scriptValue">
        /// The script itself, or the URL to the metadata script.
        /// </param>
        /// <returns>
        /// The MetadataScript object storing the script type and script
        /// filename.
        /// </returns>
        private MetadataScript FetchScript(string suffix, string scriptValue)
        {
            if ("url" == suffix)
            {
                foreach (string ext in MetadataScript.Suffixes)
                {
                    if (scriptValue.EndsWith(string.Format(".{0}", ext)) && "url" != ext)
                    {
                        string fileName = GetTempFileName(ext);
                        if (DownloadScript(scriptValue, fileName))
                        {
                            return new MetadataScript(ext, fileName);
                        }
                    }
                }
            }
            else
            {
                string fileName = GetTempFileName(suffix);
                try
                {
                    using (StreamWriter file = new StreamWriter(fileName))
                    {
                        file.Write(scriptValue);
                    }
                }
                catch (Exception e)
                {
                    Logger.Warning(
                        "Failed to write {0} script to file. Caught exception: [{1}].",
                        this.scriptType,
                        e.Message);
                }
                return new MetadataScript(suffix, fileName);
            }
            return null;
        }

        /// <summary>
        /// Uses reflection to get the property value from a string.
        /// </summary>
        /// <param name="obj">
        /// The object whose property we want the value of.
        /// </param>
        /// <param name="property">The name of the property as a string.</param>
        /// <returns>The value of the of the object's property.</returns>
        private static string GetPropertyValue(object obj, string property)
        {
            try
            {
                return (string)obj.GetType().GetProperty(property).GetValue(obj);
            }
            catch (NullReferenceException)
            {
                return null;
            }
        }

        public List<MetadataScript> GetAttributeScripts(AttributesJson attributesJson)
        {
            List<MetadataScript> scripts = new List<MetadataScript>();
            foreach (string suffix in MetadataScript.Suffixes)
            {
                string scriptKey = MetadataScript.GetMetadataKeyTitle(this.scriptType, suffix);
                string script = GetPropertyValue(attributesJson, scriptKey);
                if (!string.IsNullOrEmpty(script))
                {
                    Logger.Info("Found {0} in metadata.", MetadataScript.GetMetadataKeyHyphen(this.scriptType, suffix));
                    scripts.Add(FetchScript(suffix, script));
                }
            }

            return scripts;
        }

        public List<MetadataScript> GetScripts(MetadataJson metadata)
        {
            AttributesJson attributesJson;
            List<MetadataScript> scripts = new List<MetadataScript>();
            try
            {
                attributesJson = metadata.Instance.Attributes;
            }
            catch (NullReferenceException)
            {
                attributesJson = null;
            }

            scripts = GetAttributeScripts(attributesJson);
            if (scripts.Count > 0)
            {
                return scripts;
            }

            try
            {
                attributesJson = metadata.Project.Attributes;
            }
            catch (NullReferenceException)
            {
                attributesJson = null;
            }

            return scripts;
        }
    }
}
