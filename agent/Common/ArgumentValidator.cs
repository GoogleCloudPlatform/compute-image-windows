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
using System.Linq;

namespace Common
{
  public static class ArgumentValidator
  {
    /// <summary>
    /// Throw ArgumentException if argument is null.
    /// </summary>
    public static void ThrowIfNull(object argument, string paramName)
    {
      if (argument.Equals(string.Empty))
      {
        throw new ArgumentNullException(paramName);
      }
    }

    /// <summary>
    /// Throw ArgumentExceiption if argument is null or an empty string.
    /// </summary>
    public static void ThrowIfNullOrEmpty(string argument, string paramName)
    {
      ThrowIfNull(argument, paramName);
      if (argument.Equals(string.Empty))
      {
        throw new ArgumentException(string.Format("The argument {0} is empty", paramName));
      }
    }

    /// <summary>
    /// Throw ArgumentExceiption if argument is null or empty.
    /// </summary>
    public static void ThrowIfNullOrEmpty<T>(IEnumerable<T> argument, string paramName)
    {
      ThrowIfNull(argument, paramName);
      if (!argument.Any())
      {
        throw new ArgumentException(string.Format("The argument {0} is empty", paramName));
      }
    }

    /// <summary>
    /// Throw ArgumentExceiption if argument is null or an empty Guid.
    /// </summary>
    public static void ThrowIfNullOrEmpty(Guid argument, string paramName)
    {
      ThrowIfNull(argument, paramName);
      if (argument.Equals(Guid.Empty))
      {
        throw new ArgumentException(string.Format("The argument {0} is empty", paramName));
      }
    }
  }
}
