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
using System.Net;

namespace GCEAgent
{
  public class Manager<T>
  {
    private T metadata;
    private AgentReader<T> reader;
    private AgentWriter<T> writer;

    public Manager(AgentReader<T> reader, AgentWriter<T> writer)
    {
      this.metadata = Activator.CreateInstance<T>();
      this.reader = reader;
      this.writer = writer;
      MetadataWatcher.MetadataUpdateEvent += new MetadataWatcher.EventHandler(Synchronize);
    }

    private void Synchronize(object sender, MetadataUpdateEventArgs e)
    {
      if (reader.IsEnabled(e.metadata))
      {
        try
        {
          T metadata = (T)reader.GetMetadata(e.metadata);
          if (!reader.CompareMetadata(this.metadata, metadata))
          {
            this.metadata = metadata;
            this.writer.SetMetadata(this.metadata);
          }
        }
        catch (Exception ex)
        {
          Logger.Error("Caught top level exception. {0}\r\n{1}", ex.Message, ex.StackTrace);
        }
      }
    }
  }

  public class AccountsManager : Manager<List<WindowsKey>>
  {
    public AccountsManager() : base(new AccountsReader(), new AccountsWriter()) { }
  }

  public class AddressManager : Manager<List<IPAddress>>
  {
    public AddressManager() : base(new AddressReader(), new AddressWriter()) { }
  }
}
