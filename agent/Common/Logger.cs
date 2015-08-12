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
using System.Diagnostics;
using System.IO.Ports;
using System.Threading;

namespace Common
{
  public static class Logger
  {
    private const string DEFAULT_COM = "COM1";
    private const string EVENT_SOURCE = "Google Service";
    private const string LOG_NAME = "Google";
    private const int RETRY_LIMIT = 5;
    private static EventLog log;
    public struct EntryType
    {
      public const EventLogEntryType Info = EventLogEntryType.Information;
      public const EventLogEntryType Warning = EventLogEntryType.Warning;
      public const EventLogEntryType Error = EventLogEntryType.Error;
    }

    static Logger()
    {
      if (!EventLog.SourceExists(EVENT_SOURCE))
      {
        EventLog.CreateEventSource(EVENT_SOURCE, LOG_NAME);
      }

      log = new EventLog();
      log.Source = EVENT_SOURCE;
    }

    private static void Log(SerialPort port, string entry)
    {
      int attempt = 1;
      while (true)
      {
        try
        {
          if (!port.IsOpen)
          {
            port.Open();
          }
          port.WriteLine(entry);
          break;
        }
        catch (UnauthorizedAccessException)
        {
          if (attempt++ >= RETRY_LIMIT)
          {
            throw;
          }
          port.Close();
          // Sleep for one second before trying again.
          Thread.Sleep(1000);
        }
      }
    }

    public static void LogWithCom(EventLogEntryType type, string com, string format, params object[] args)
    {
      // Add the date to any log message sent to COM1.
      if (DEFAULT_COM == com)
      {
        format = string.Format("{0} UTC: {1}", DateTime.UtcNow, format);
      }

      string entry = string.Format(format, args);

      // Write to the event log
      log.WriteEntry(entry, type);

      // Also write to the COM port.
      using (SerialPort port = new SerialPort(com))
      {
        Log(port, entry);
      }
    }

    public static void Info(string format, params object[] args)
    {
      LogWithCom(EntryType.Info, DEFAULT_COM, format, args);
    }

    public static void Warning(string format, params object[] args)
    {
      LogWithCom(EntryType.Warning, DEFAULT_COM, format, args);
    }

    public static void Error(string format, params object[] args)
    {
      LogWithCom(EntryType.Error, DEFAULT_COM, format, args);
    }
  }
}
