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
using System.Net;
using System.Threading;
using System.Threading.Tasks;

namespace Common
{
  public class MetadataUpdateEventArgs : EventArgs
  {
    public MetadataJson metadata { get; private set; }

    public MetadataUpdateEventArgs(MetadataJson metadata)
    {
      this.metadata = metadata;
    }
  }

  public class MetadataWatcher
  {
    private const string METADATA_SERVER = "http://metadata.google.internal/computeMetadata/v1";
    private const string METADATA_HANG = "/?recursive=true&alt=json&wait_for_change=true&timeout_sec=60&last_etag=";
    private const string DEFAULT_ETAG = "NONE";
    private const int REQUEST_TIMEOUT = 70 * 1000; // 70 seconds in case of an abandoned request.

    // Make the MetadataWatcher a singleton object.
    private static readonly MetadataWatcher watcher = new MetadataWatcher();
    private MetadataWatcher() { }
    public static MetadataWatcher Watcher { get { return watcher; } }

    // Store the Etag used for subsequent retrievals of metadata.
    private static string Etag { get; set; }

    // Flag indicating if we should print a WebException.
    // Web exceptions should only be printed once, and then a success message should follow.
    private static bool PrintWebException { get; set; }

    // Use the CancellationToken as an exit condition.
    private static CancellationTokenSource Token { get; set; }

    public delegate void EventHandler(object sender, MetadataUpdateEventArgs e);
    public static event EventHandler MetadataUpdateEvent;

    private static void ActivateMetadataUpdate(MetadataJson metadata)
    {
      MetadataUpdateEventArgs eventArgs = new MetadataUpdateEventArgs(metadata);
      if (MetadataUpdateEvent != null)
      {
        MetadataUpdateEvent(null, eventArgs);
      }
    }

    /// <summary>
    /// Creates a WebRequest to the metadata server given a URL.
    /// </summary>
    private static WebRequest CreateRequest(string metadataRequest)
    {
      HttpWebRequest request = WebRequest.CreateHttp(metadataRequest);
      request.Headers.Add("X-Google-Metadata-Request", "True");
      request.Timeout = REQUEST_TIMEOUT;
      return request;
    }

    /// <summary>
    /// The etag determines whether the content of the metadata server
    /// has changed. We reset the etag at initialization. Resetting the
    /// etag will result in an immediate response from anything that waits
    /// for a change in the metadata server contents.
    /// </summary>
    private static void ResetEtag()
    {
      Etag = DEFAULT_ETAG;
    }

    private static void UpdateEtag(WebResponse response)
    {
      Etag = response.Headers.Get("etag");
      if (Etag == null)
      {
        ResetEtag();
      }
    }

    /// <summary>
    /// Makes a hanging get request against the metadata server.
    /// Marked async so the cancellation token from the main loop can terminate this wait.
    /// </summary>
    private static async Task<string> WaitForUpdate()
    {
      WebRequest request = CreateRequest(METADATA_SERVER + METADATA_HANG + Etag);
      try
      {
        using (WebResponse response = await request.GetResponseAsync())
        {
          UpdateEtag(response);
          using (StreamReader sr = new StreamReader(response.GetResponseStream()))
          {
            return await sr.ReadToEndAsync();
          }
        }
      }
      catch (WebException e)
      {
        if (PrintWebException)
        {
          Logger.Warning("WebException waiting for metadata change: {0}", e.Message);
          PrintWebException = false;
        }

        ResetEtag();
        throw;
      }
      catch (Exception e)
      {
        Logger.Error("Exception waiting for metadata change: {0}", e.Message);
        throw;
      }
    }

    /// <summary>
    /// Wait for metadata changes until cancellation is requested.
    /// Deserialize the response from the metadata server into a JSON object.
    /// Emit an event with this object indicating the metadata server content
    /// has updated.
    /// </summary>
    private static async Task<string> GetMetadataUpdate()
    {
      try
      {
        string metadata = await WaitForUpdate();

        // There are no network issues if we reach this point.
        if (!PrintWebException)
        {
          PrintWebException = true;
          Logger.Warning("Network access restored.");
        }

        return metadata;
      }
      catch (WebException e)
      {
        if (PrintWebException)
        {
          Logger.Warning("WebException responding to metadata server update: {0}", e.Message);
          PrintWebException = false;
        }

        // Sleep for five seconds before trying again.
        Thread.Sleep(5000);
      }
      catch (Exception e)
      {
        // Log Exception and try again.
        Logger.Error("Exception responding to metadata server update: {0}\n{1}", e.Message, e.StackTrace);
      }

      return null;
    }

    /// <summary>
    /// Wait for metadata changes until cancellation is requested.
    /// </summary>
    private static async void WatchMetadata()
    {
      while (!Token.IsCancellationRequested)
      {
        string metadata = await GetMetadataUpdate();

        // Check if the response from deserialize is null.
        if (!string.IsNullOrEmpty(metadata))
        {
          MetadataJson metadataJson = MetadataDeserializer.DeserializeMetadata<MetadataJson>(metadata);
          ActivateMetadataUpdate(metadataJson);
        }
      }
    }

    /// <summary>
    /// Updates the CancellationToken and starts the Metadata Watcher.
    /// The CancellationToken represents the exit condition for
    /// watching the metadata server contents.
    /// </summary>
    public static void UpdateToken(CancellationTokenSource tokenSource)
    {
      Token = tokenSource;
      ResetEtag();
      PrintWebException = true;
      WatchMetadata();
    }

    /// <summary>
    /// Synchronously waits and retrieves metadata server contents.
    /// </summary>
    /// <returns>The deserialized contents of the metadata server.</returns>
    public static MetadataJson GetMetadata()
    {
      ResetEtag();
      PrintWebException = true;
      string metadata;
      do
      {
        metadata = GetMetadataUpdate().Result;
      }
      while (string.IsNullOrEmpty(metadata));
      return MetadataDeserializer.DeserializeMetadata<MetadataJson>(metadata);
    }
  }
}
