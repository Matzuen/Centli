#pragma once
// Minimal ATL string-conversion stubs for flutter_secure_storage_windows.
// That plugin only needs CA2W / CW2A from <atlstr.h>. Prefer installing the
// real VS component "C++ ATL for latest v145 build tools (x86 & x64)" when
// possible; this stub lets the Windows build proceed without it.

#ifndef CENTLI_ATL_STUB_ATLSTR_H_
#define CENTLI_ATL_STUB_ATLSTR_H_

#include <windows.h>

class CA2W {
 public:
  LPWSTR m_psz;

  explicit CA2W(LPCSTR psz) : m_psz(nullptr) {
    if (psz == nullptr) {
      return;
    }
    const int n = MultiByteToWideChar(CP_ACP, 0, psz, -1, nullptr, 0);
    if (n <= 0) {
      return;
    }
    m_psz = new wchar_t[static_cast<size_t>(n)];
    MultiByteToWideChar(CP_ACP, 0, psz, -1, m_psz, n);
  }

  ~CA2W() { delete[] m_psz; }

  CA2W(const CA2W&) = delete;
  CA2W& operator=(const CA2W&) = delete;

  operator LPWSTR() const { return m_psz; }
};

class CW2A {
 public:
  LPSTR m_psz;

  explicit CW2A(LPCWSTR psz) : m_psz(nullptr) {
    if (psz == nullptr) {
      return;
    }
    const int n =
        WideCharToMultiByte(CP_ACP, 0, psz, -1, nullptr, 0, nullptr, nullptr);
    if (n <= 0) {
      return;
    }
    m_psz = new char[static_cast<size_t>(n)];
    WideCharToMultiByte(CP_ACP, 0, psz, -1, m_psz, n, nullptr, nullptr);
  }

  ~CW2A() { delete[] m_psz; }

  CW2A(const CW2A&) = delete;
  CW2A& operator=(const CW2A&) = delete;

  operator LPSTR() const { return m_psz; }
};

#endif  // CENTLI_ATL_STUB_ATLSTR_H_
