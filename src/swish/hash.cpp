// Copyright 2017 Beckman Coulter, Inc.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include "stdafx.h"

void hash_init()
{
  DEFINE_FOREIGN(osi::OpenHash);
  DEFINE_FOREIGN(osi::HashData);
  DEFINE_FOREIGN(osi::GetHashValue);
  DEFINE_FOREIGN(osi::CloseHash);
}

static HCRYPTPROV g_CryptProvider = NULL;
HashMap g_Hashes;

static inline const HCRYPTHASH& LookupHash(iptr hash)
{
  static HCRYPTHASH missing = 0;
  return g_Hashes.Lookup(hash, missing);
}

ptr osi::OpenHash(ALG_ID alg)
{
  if (NULL == g_CryptProvider)
  {
    if (!CryptAcquireContext(&g_CryptProvider, NULL, MS_ENH_RSA_AES_PROV, PROV_RSA_AES, CRYPT_VERIFYCONTEXT))
      return MakeLastErrorPair("CryptAcquireContextW");
  }
  HCRYPTHASH h;
  if (!CryptCreateHash(g_CryptProvider, alg, 0, 0, &h))
    return MakeLastErrorPair("CryptCreateHash");
  return Sfixnum(g_Hashes.Allocate(h));
}

ptr osi::HashData(iptr hash, ptr buffer, size_t startIndex, UINT32 size)
{
  HCRYPTHASH h = LookupHash(hash);
  if (NULL == h)
    return MakeErrorPair("osi::HashData", ERROR_INVALID_HANDLE);
  size_t last = startIndex + size;
  if (!Sbytevectorp(buffer) ||
    (last < startIndex) || // startIndex + size overflowed
    (last > static_cast<size_t>(Sbytevector_length(buffer))))
    return MakeErrorPair("osi::HashData", ERROR_BAD_ARGUMENTS);
  if (!CryptHashData(h, &Sbytevector_u8_ref(buffer, startIndex), size, 0))
    return MakeLastErrorPair("CryptHashData");
  return Strue;
}

ptr osi::GetHashValue(iptr hash)
{
  HCRYPTHASH h = LookupHash(hash);
  if (NULL == h)
    return MakeErrorPair("osi::GetHashValue", ERROR_INVALID_HANDLE);
  DWORD hashsize;
  DWORD n = sizeof(hashsize);
  if (!CryptGetHashParam(h, HP_HASHSIZE, (BYTE*)&hashsize, &n, 0))
    return MakeLastErrorPair("CryptGetHashParam");
  ptr r = Smake_bytevector(hashsize, 0);
  if (!CryptGetHashParam(h, HP_HASHVAL, Sbytevector_data(r), &hashsize, 0))
    return MakeLastErrorPair("CryptGetHashParam");
  return r;
}

ptr osi::CloseHash(iptr hash)
{
  HCRYPTHASH h = LookupHash(hash);
  if (NULL == h)
    return MakeErrorPair("osi::CloseHash", ERROR_INVALID_HANDLE);
  CryptDestroyHash(h);
  g_Hashes.Deallocate(hash);
  return Strue;
}
