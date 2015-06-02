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

using Common;
using System;
using System.Collections.Generic;

namespace GCEMetadataScripts
{
  public class ScriptManager
  {
    private List<MetadataScript> metadata;
    private ScriptReader reader;
    private ScriptWriter writer;
    private string scriptType;

    public ScriptManager(string scriptType)
    {
      this.scriptType = scriptType;
      this.reader = new ScriptReader(scriptType);
      this.writer = new ScriptWriter(scriptType);
      RunScripts();
    }

    private void RunScripts()
    {
      Logger.Info("Starting {0} scripts...", this.scriptType);
      MetadataJson metadata = MetadataWatcher.GetMetadata();
      this.metadata = reader.GetScripts(metadata);
      this.writer.SetScripts(this.metadata);
      Logger.Info("Finished running {0} scripts.", this.scriptType);
    }

    private static string ValidateArguments(string[] args)
    {
      if (args == null || args.Length == 0)
      {
        return null;
      }
      string scriptKey = args[0].ToLower();
      return MetadataScript.ScriptTypes.Contains(scriptKey) ? scriptKey : null;
    }

    static void Main(string[] args)
    {
      string scriptType = ValidateArguments(args);
      if (string.IsNullOrEmpty(scriptType))
      {
        string validOptions = string.Join(", ", MetadataScript.ScriptTypes);
        throw new Exception(string.Format("No valid arguments specified. Options: [{0}]", validOptions));
      }
      ScriptManager manager = new ScriptManager(scriptType);
    }
  }
}
