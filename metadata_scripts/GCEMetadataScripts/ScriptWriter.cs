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
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Google.ComputeEngine.Common;

namespace Google.ComputeEngine.MetadataScripts
{
    public sealed class ScriptWriter
    {
        private readonly string scriptType;

        public ScriptWriter(string scriptType)
        {
            this.scriptType = scriptType;
        }

        private ProcessStartInfo GetProcStartInfo(string filename, string arguments = "")
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = filename;
            startInfo.Arguments = arguments;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            return startInfo;
        }

        private ProcessStartInfo RunPowershell(string script)
        {
            string arguments = string.Format("-ExecutionPolicy ByPass -File {0}", script);
            return GetProcStartInfo(@"C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe", arguments);
        }

        private void LogScriptOutput(string suffix, string message)
        {
            string script = MetadataScript.GetMetadataKeyHyphen(this.scriptType, suffix);
            if (!string.IsNullOrEmpty(message))
            {
                Logger.Info("{0}: {1}", script, message);
            }
        }

        private async Task LogStream(string suffix, StreamReader reader)
        {
            string readText;
            using (reader)
            {
                while ((readText = await reader.ReadLineAsync()) != null)
                {
                    LogScriptOutput(suffix, readText);
                }
            }
        }

        public async Task RunScript(MetadataScript metadataScript)
        {
            ProcessStartInfo startInfo;

            if ("ps1" == metadataScript.Suffix)
            {
                startInfo = RunPowershell(metadataScript.Script);
            }
            else
            {
                startInfo = GetProcStartInfo(metadataScript.Script);
            }

            using (Process process = Process.Start(startInfo))
            {
                Task outputFinished = LogStream(metadataScript.Suffix, process.StandardOutput);
                await LogStream(metadataScript.Suffix, process.StandardError);
                await outputFinished;
            }
            File.Delete(metadataScript.Script);
        }

        public void SetScripts(List<MetadataScript> metadata)
        {
            foreach (MetadataScript metadataScript in metadata)
            {
                if (metadataScript != null)
                {
                    RunScript(metadataScript).Wait();
                }
            }
        }
    }
}
