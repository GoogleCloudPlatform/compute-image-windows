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

using Microsoft.Win32.SafeHandles;
using System;
using System.Runtime.ConstrainedExecution;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;

namespace GCEAgent
{
  public static class NativeMethods
  {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword,
      int dwLogonType, int dwLogonProvider, out SafeTokenHandle phToken);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    public extern static bool CloseHandle(IntPtr handle);

    [DllImport("iphlpapi.dll", SetLastError = true)]
    public static extern int AddIPAddress(
        int address, int mask, int interfaceIndex, out IntPtr nteContext, out IntPtr nteInstances);

    [DllImport("iphlpapi.dll", SetLastError = true)]
    public static extern int DeleteIPAddress(IntPtr nteContext);

    [DllImport("iphlpapi.dll", CharSet = CharSet.Ansi)]
    public static extern int GetAdaptersInfo(IntPtr adapterInfoBuffer, ref int bufferLength);

    [DllImport("NetApi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern NetUserRetEnum NetUserAdd(
        string ServerName,
        uint Level,
        ref USER_INFO_1 Buf,
        out uint ParmError);

    [DllImport("NetApi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern NetUserRetEnum NetUserSetInfo(
        string ServerName,
        string UserName,
        uint Level,
        ref USER_INFO_1 Buf,
        out uint ParmError);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LookupAccountName(
        string lpSystemName,
        string lpAccountName,
        [MarshalAs(UnmanagedType.LPArray)]
        byte[] Sid,
        ref uint cbSid,
        StringBuilder ReferencedDomainName,
        ref uint cchReferencedDomainName,
        out SID_NAME_USE peUse);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LookupAccountSid(
        string lpSystemName,
        [MarshalAs(UnmanagedType.LPArray)]
        byte[] lpSid,
        StringBuilder lpName,
        ref uint cchName,
        StringBuilder lpReferencedDomainName,
        ref uint cchReferencedDomainName,
        out SID_NAME_USE peUse);

    [DllImport("NetApi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern NetUserRetEnum NetLocalGroupAddMembers(
        string Servername,
        string Groupname,
        uint Level,
        ref LOCALGROUP_MEMBERS_INFO_0 Buf,
        uint Totalentries);

    [DllImport("NetApi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern NetUserRetEnum NetUserDel(string ServerName, string UserName);

    public enum NetUserRetEnum
    {
      NERR_Success = 0,
      ERROR_ACCESS_DENIED = 5,
      ERROR_INVALID_PARAMETER = 87,
      NERR_InvalidComputer = 2351,  // This computer name is invalid.
      NERR_NotPrimary = 2226,       // This operation is only allowed on the primary domain controller.
      NERR_SpeGroupOp = 2234,       // This operation is not allowed on this special group.
      NERR_LastAdmin = 2452,        // This operation is not allowed on the last administrative account.
      NERR_BadPassword = 2203,      // The password parameter is invalid.
      NERR_PasswordTooShort = 2245, // The password does not meet the password policy requirements.
      NERR_UserNotFound = 2221,     // The user name could not be found.
      NERR_GroupExists = 2223,      // The group already exists.
      NERR_UserExists = 2224,       // The user account already exists.
    };

    public enum SID_NAME_USE
    {
      SidTypeUser = 1,
      SidTypeGroup,
      SidTypeDomain,
      SidTypeAlias,
      SidTypeWellKnownGroup,
      SidTypeDeletedAccount,
      SidTypeInvalid,
      SidTypeUnknown,
      SidTypeComputer,
    }

    private const int MAX_ADAPTER_ADDRESS_LENGTH = 8;
    private const int MAX_ADAPTER_DESCRIPTION_LENGTH = 128;
    private const int MAX_ADAPTER_NAME_LENGTH = 256;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct IP_ADDRESS_STRING
    {
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 16)]
      public string Address;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct IP_ADDR_STRING
    {
      public IntPtr Next;
      public IP_ADDRESS_STRING IpAddress;
      public IP_ADDRESS_STRING IpMask;
      public int Context;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct IP_ADAPTER_INFO
    {
      public IntPtr Next;
      public int ComboIndex;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MAX_ADAPTER_NAME_LENGTH + 4)]
      public string AdapterName;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MAX_ADAPTER_DESCRIPTION_LENGTH + 4)]
      public string AdapterDescription;
      public uint AddressLength;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst = MAX_ADAPTER_ADDRESS_LENGTH)]
      public byte[] Address;
      public int Index;
      public uint Type;
      public uint DhcpEnabled;
      public IntPtr CurrentIpAddress;
      public IP_ADDR_STRING IpAddressList;
      public IP_ADDR_STRING GatewayList;
      public IP_ADDR_STRING DhcpServer;
      public bool HaveWins;
      public IP_ADDR_STRING PrimaryWinsServer;
      public IP_ADDR_STRING SecondaryWinsServer;
      public int LeaseObtained;
      public int LeaseExpires;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct USER_INFO_1
    {
      public string usri1_name;
      public string usri1_password;
      public uint usri1_password_age;
      public uint usri1_priv;
      public string usri1_home_dir;
      public string usri1_comment;
      public uint usri1_flags;
      public string usri1_script_path;
    }

    public struct LOCALGROUP_MEMBERS_INFO_0
    {
        public IntPtr PSID;
    }
  }

  public sealed class SafeTokenHandle : SafeHandleZeroOrMinusOneIsInvalid
  {
      private SafeTokenHandle()
          : base(true)
      {
      }

      [DllImport("kernel32.dll")]
      [ReliabilityContract(Consistency.WillNotCorruptState, Cer.Success)]
      [SuppressUnmanagedCodeSecurity]
      [return: MarshalAs(UnmanagedType.Bool)]
      private static extern bool CloseHandle(IntPtr handle);

      protected override bool ReleaseHandle()
      {
          return CloseHandle(handle);
      }
  }
}
