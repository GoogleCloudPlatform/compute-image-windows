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
using System.Globalization;

namespace Google.ComputeEngine.MetadataScripts
{
    public sealed class MetadataScript
    {
        public static List<string> ScriptTypes = new List<string> { "shutdown", "specialize", "startup" };
        public static List<string> Suffixes = new List<string> { "ps1", "cmd", "bat", "url" };
        public string Suffix { get; private set; }
        public string Script { get; private set; }

        public MetadataScript(string suffix, string script)
        {
            this.Suffix = suffix;
            this.Script = script;
        }

        private static readonly Dictionary<string, string> ScriptTypesDict = new Dictionary<string, string>()
        {
            { "shutdown", "windows shutdown script" },
            { "specialize", "sysprep specialize script" },
            { "startup", "windows startup script" },
        };

        /// <summary>
        /// Converts script type and script suffix into a space separated
        /// string.
        /// </summary>
        /// <param name="scriptType">The script type e.g. "specialize".</param>
        /// <param name="suffix">The script suffix e.g. "ps1".</param>
        /// <returns>
        /// Space separated key e.g. "sysprep specialize script ps1".
        /// </returns>
        public static string GetMetadataTypeString(string scriptType, string suffix)
        {
            string scriptTypeString = string.Empty;
            if (ScriptTypesDict.TryGetValue(scriptType, out scriptTypeString))
            {
                scriptTypeString = string.Format("{0} {1}", scriptTypeString, suffix);
            }
            return scriptTypeString;
        }

        /// <summary>
        /// Converts script type and suffix into a metadata key in title case.
        /// </summary>
        /// <returns>
        /// The metadata key e.g. "SysprepSpecializeScriptPs1".
        /// </returns>
        public static string GetMetadataKeyTitle(string scriptType, string suffix)
        {
            TextInfo textInfo = new CultureInfo("en-US", false).TextInfo;
            string scriptTypeString = textInfo.ToTitleCase(GetMetadataTypeString(scriptType, suffix));
            return string.Join(null, scriptTypeString.Split(new char[] { ' ' }));
        }

        /// <summary>
        /// Converts script type and suffix into a metadata key in hyphen case.
        /// </summary>
        /// <returns>
        /// The metadata key e.g. "sysprep-specialize-script-ps1".
        /// </returns>
        public static string GetMetadataKeyHyphen(string scriptType, string suffix)
        {
            string scriptTypeString = GetMetadataTypeString(scriptType, suffix);
            return string.Join("-", scriptTypeString.Split(new char[] { ' ' }));
        }
    }
}
