#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_MACROS_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_MACROS_H_

#include "stdafx.h"

// Utility macros.

#define GEN_EVAL(X) X
#define GEN_STRINGIZE_ARG(X) #X
#define GEN_STRINGIZE(X) GEN_EVAL(GEN_STRINGIZE_ARG(X))
#define GEN_MERGE(A, B) A##B
#define GEN_MAKE_W(A) GEN_MERGE(L, A)
#define GEN_WSTRINGIZE(X) GEN_MAKE_W(GEN_STRINGIZE_ARG(X))
#define __WFILE__ GEN_MAKE_W(GEN_EVAL(__FILE__))
#define __WFUNCTION__ GEN_MAKE_W(GEN_EVAL(__FUNCTION__))

// Helper macros to print a GUID.
#define WSTR_GUID_FMT  L"{%.8x-%.4x-%.4x-%.2x%.2x-%.2x%.2x%.2x%.2x%.2x%.2x}"

#define GUID_PRINTF_ARG(X)                                 \
  (X).Data1,                                               \
  (X).Data2,                                               \
  (X).Data3,                                               \
  (X).Data4[0], (X).Data4[1], (X).Data4[2], (X).Data4[3],  \
  (X).Data4[4], (X).Data4[5], (X).Data4[6], (X).Data4[7]

// Helper macro for quick treatment of case statements for error codes.
#define CHECK_CONSTANT(value)                     \
  case value: return wstring(GEN_MAKE_W(#value));

#define BOOL2TXT(b) ((b)? L"TRUE": L"FALSE")

// Macro that express the position in the source file.
#define DBG_INFO        __WFILE__ , __LINE__, __WFUNCTION__

#endif   // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_MACROS_H_
