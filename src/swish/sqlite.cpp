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

void sqlite_init()
{
  DEFINE_FOREIGN(osi::OpenDatabase);
  DEFINE_FOREIGN(osi::CloseDatabase);
  DEFINE_FOREIGN(osi::PrepareStatement);
  DEFINE_FOREIGN(osi::FinalizeStatement);
  DEFINE_FOREIGN(osi::BindStatement);
  DEFINE_FOREIGN(osi::ClearStatementBindings);
  DEFINE_FOREIGN(osi::GetLastInsertRowid);
  DEFINE_FOREIGN(osi::GetStatementColumns);
  DEFINE_FOREIGN(osi::GetStatementSQL);
  DEFINE_FOREIGN(osi::ResetStatement);
  DEFINE_FOREIGN(osi::StepStatement);
  DEFINE_FOREIGN(osi::GetSQLiteStatus);
}

DatabaseMap g_Databases;
StatementMap g_Statements;

static inline const DatabaseEntry& LookupDatabase(iptr database)
{
  static DatabaseEntry missing = {0};
  return g_Databases.Lookup(database, missing);
}

static void SetDatabaseBusy(iptr database, bool busy)
{
  g_Databases.Map.find(database)->second.busy = busy;
}

static inline const StatementEntry& LookupStatement(iptr statement)
{
  static StatementEntry missing = {0};
  return g_Statements.Lookup(statement, missing);
}

static inline ptr MakeSQLiteErrorPair(const char* who, int rc)
{
  return MakeErrorPair(who, rc + 600000000);
}

ptr osi::OpenDatabase(ptr filename, int flags)
{
  if (!Sstringp(filename))
    return MakeErrorPair("osi::OpenDatabase", ERROR_BAD_ARGUMENTS);
  UTF8String u8filename(filename);
  DatabaseEntry dbe;
  dbe.busy = false;
  int rc = sqlite3_open_v2(u8filename.GetBuffer(), &(dbe.db), flags, NULL);
  if (SQLITE_OK != rc)
  {
    if (dbe.db)
    {
      rc = sqlite3_extended_errcode(dbe.db);
      sqlite3_close(dbe.db);
    }
    return MakeSQLiteErrorPair("sqlite3_open_v2", rc);
  }
  sqlite3_extended_result_codes(dbe.db, 1);
  return Sfixnum(g_Databases.Allocate(dbe));
}

ptr osi::CloseDatabase(iptr database)
{
  DatabaseEntry dbe = LookupDatabase(database);
  if (NULL == dbe.db)
    return MakeErrorPair("osi::CloseDatabase", ERROR_INVALID_HANDLE);
  if (dbe.busy)
    return MakeErrorPair("osi::CloseDatabase", ERROR_ACCESS_DENIED);
  std::list<iptr> toDeallocate;
  for (StatementMap::TMap::const_iterator iter = g_Statements.Map.begin(); iter != g_Statements.Map.end(); iter++)
    if (database == iter->second.db_handle)
    {
      sqlite3_finalize(iter->second.stmt);
      toDeallocate.push_back(iter->first);
    }
  for (std::list<iptr>::const_iterator iter = toDeallocate.begin(); iter != toDeallocate.end(); iter++)
    g_Statements.Deallocate(*iter);
  int rc = sqlite3_close(dbe.db);
  if (SQLITE_OK != rc)
    return MakeSQLiteErrorPair("sqlite3_close", rc);
  g_Databases.Deallocate(database);
  return Strue;
}

ptr osi::PrepareStatement(iptr database, ptr sql)
{
  if (!Sstringp(sql))
    return MakeErrorPair("osi::PrepareStatement", ERROR_BAD_ARGUMENTS);
  DatabaseEntry dbe = LookupDatabase(database);
  if (NULL == dbe.db)
    return MakeErrorPair("osi::PrepareStatement", ERROR_INVALID_HANDLE);
  if (dbe.busy)
    return MakeErrorPair("osi::PrepareStatement", ERROR_ACCESS_DENIED);
  UTF8String u8sql(sql);
  size_t len = u8sql.GetLength();
  if (len > MAXLONG)
    return MakeSQLiteErrorPair("sqlite3_prepare_v2", SQLITE_TOOBIG);
  StatementEntry ste;
  ste.db_handle = database;
  int rc = sqlite3_prepare_v2(dbe.db, u8sql.GetBuffer(), static_cast<long>(len), &(ste.stmt), NULL);
  if (SQLITE_OK != rc)
    return MakeSQLiteErrorPair("sqlite3_prepare_v2", rc);
  return Sfixnum(g_Statements.Allocate(ste));
}

ptr osi::FinalizeStatement(iptr statement)
{
  StatementEntry ste = LookupStatement(statement);
  if (NULL == ste.stmt)
    return MakeErrorPair("osi::FinalizeStatement", ERROR_INVALID_HANDLE);
  if (LookupDatabase(ste.db_handle).busy)
    return MakeErrorPair("osi::FinalizeStatement", ERROR_ACCESS_DENIED);
  sqlite3_finalize(ste.stmt);
  g_Statements.Deallocate(statement);
  return Strue;
}

ptr osi::BindStatement(iptr statement, UINT index, ptr datum)
{
  StatementEntry ste = LookupStatement(statement);
  if (NULL == ste.stmt)
    return MakeErrorPair("osi::BindStatement", ERROR_INVALID_HANDLE);
  if (LookupDatabase(ste.db_handle).busy)
    return MakeErrorPair("osi::BindStatement", ERROR_ACCESS_DENIED);
  int rc;
  const char* who;
  if (Sfalse == datum)
  {
    who = "sqlite3_bind_null";
    rc = sqlite3_bind_null(ste.stmt, index);
  }
  else if (Sfixnump(datum) || Sbignump(datum))
  {
    who = "sqlite3_bind_int64";
    rc = sqlite3_bind_int64(ste.stmt, index, Sinteger64_value(datum));
  }
  else if (Sflonump(datum))
  {
    who = "sqlite3_bind_double";
    rc = sqlite3_bind_double(ste.stmt, index, Sflonum_value(datum));
  }
  else if (Sstringp(datum))
  {
    UTF8String u8text(datum);
    who = "sqlite3_bind_text";
    size_t len = u8text.GetLength() - 1;
    if (len > MAXLONG)
      rc = SQLITE_TOOBIG;
    else
      rc = sqlite3_bind_text(ste.stmt, index, u8text.GetBuffer(), static_cast<long>(len), SQLITE_TRANSIENT);
  }
  else if (Sbytevectorp(datum))
  {
    who = "sqlite3_bind_blob";
    size_t len = Sbytevector_length(datum);
    if (len <= MAXLONG)
      rc = sqlite3_bind_blob(ste.stmt, index, (const void*)Sbytevector_data(datum), (long)len, SQLITE_TRANSIENT);
    else
      rc = SQLITE_TOOBIG;
  }
  else
    return MakeErrorPair("osi::BindStatement", ERROR_BAD_ARGUMENTS);
  if (SQLITE_OK != rc)
    return MakeSQLiteErrorPair(who, rc);
  return Strue;
}

ptr osi::ClearStatementBindings(iptr statement)
{
  StatementEntry ste = LookupStatement(statement);
  if (NULL == ste.stmt)
    return MakeErrorPair("osi::ClearStatementBindings", ERROR_INVALID_HANDLE);
  if (LookupDatabase(ste.db_handle).busy)
    return MakeErrorPair("osi::ClearStatementBindings", ERROR_ACCESS_DENIED);
  int rc = sqlite3_clear_bindings(ste.stmt);
  if (SQLITE_OK != rc)
    return MakeSQLiteErrorPair("sqlite3_clear_bindings", rc);
  return Strue;
}

ptr osi::GetLastInsertRowid(iptr database)
{
  DatabaseEntry dbe = LookupDatabase(database);
  if (NULL == dbe.db)
    return MakeErrorPair("osi::GetLastInsertRowid", ERROR_INVALID_HANDLE);
  if (dbe.busy)
    return MakeErrorPair("osi::GetLastInsertRowid", ERROR_ACCESS_DENIED);
  return Sinteger64(sqlite3_last_insert_rowid(dbe.db));
}

ptr osi::GetStatementColumns(iptr statement)
{
  StatementEntry ste = LookupStatement(statement);
  if (NULL == ste.stmt)
    return MakeErrorPair("osi::GetStatementColumns", ERROR_INVALID_HANDLE);
  if (LookupDatabase(ste.db_handle).busy)
    return MakeErrorPair("osi::GetStatementColumns", ERROR_ACCESS_DENIED);
  int count = sqlite3_column_count(ste.stmt);
  ptr v = Smake_vector(count, Sfixnum(0));
  for (int i=0; i < count; ++i)
  {
    ptr name = MakeSchemeString(sqlite3_column_name(ste.stmt, i));
    if (Spairp(name))
      return name;
    Svector_set(v, i, name);
  }
  return v;
}

ptr osi::GetStatementSQL(iptr statement)
{
  StatementEntry ste = LookupStatement(statement);
  if (NULL == ste.stmt)
    return MakeErrorPair("osi::GetStatementSQL", ERROR_INVALID_HANDLE);
  if (LookupDatabase(ste.db_handle).busy)
    return MakeErrorPair("osi::GetStatementSQL", ERROR_ACCESS_DENIED);
  return MakeSchemeString(sqlite3_sql(ste.stmt));
}

ptr osi::ResetStatement(iptr statement)
{
  StatementEntry ste = LookupStatement(statement);
  if (NULL == ste.stmt)
    return MakeErrorPair("osi::ResetStatement", ERROR_INVALID_HANDLE);
  if (LookupDatabase(ste.db_handle).busy)
    return MakeErrorPair("osi::ResetStatement", ERROR_ACCESS_DENIED);
  int rc = sqlite3_reset(ste.stmt);
  if (SQLITE_OK != rc)
    return MakeSQLiteErrorPair("sqlite3_reset", rc);
  return Strue;
}

ptr osi::StepStatement(iptr statement, ptr callback)
{
  class Stepper : public WorkItem
  {
  public:
    sqlite3_stmt* Stmt;
    iptr Database;
    ptr Callback;
    Stepper(sqlite3_stmt* stmt, iptr database, ptr callback)
    {
      Stmt = stmt;
      Database = database;
      Callback = callback;
      SetDatabaseBusy(Database, true);
      Slock_object(Callback);
    }
    virtual ~Stepper()
    {
      SetDatabaseBusy(Database, false);
      Sunlock_object(Callback);
    }
    virtual DWORD Work()
    {
      return sqlite3_step(Stmt);
    }
    virtual ptr GetCompletionPacket(DWORD error)
    {
      sqlite3_stmt* stmt = Stmt;
      ptr callback = Callback;
      delete this;
      ptr arg;
      if (SQLITE_DONE == error)
        arg = Sfalse;
      else if (SQLITE_ROW == error)
      {
        int n = sqlite3_column_count(stmt);
        arg = Smake_vector(n, Sfixnum(0));
        for (int i = 0; i < n; i++)
        {
          ptr x;
          switch (sqlite3_column_type(stmt, i))
          {
          case SQLITE_NULL:
            x = Sfalse;
            break;
          case SQLITE_INTEGER:
            x = Sinteger64(sqlite3_column_int64(stmt, i));
            break;
          case SQLITE_FLOAT:
            x = Sflonum(sqlite3_column_double(stmt, i));
            break;
          case SQLITE_TEXT:
            {
              const char* text = (const char*)sqlite3_column_text(stmt, i);
              x = MakeSchemeString(text, sqlite3_column_bytes(stmt, i));
              if (Spairp(x))
                return MakeList(callback, x);
              break;
            }
          default: // SQLITE_BLOB
            {
              const void* blob = sqlite3_column_blob(stmt, i);
              int n = sqlite3_column_bytes(stmt, i);
              x = Smake_bytevector(n, 0);
              memcpy(Sbytevector_data(x), blob, n);
            }
          }
          Svector_set(arg, i, x);
        }
      }
      else
        arg = MakeSQLiteErrorPair("sqlite3_step", error);
      return MakeList(callback, arg);
    }
  };

  StatementEntry ste = LookupStatement(statement);
  if (NULL == ste.stmt)
    return MakeErrorPair("osi::StepStatement", ERROR_INVALID_HANDLE);
  if (LookupDatabase(ste.db_handle).busy)
    return MakeErrorPair("osi::StepStatement", ERROR_ACCESS_DENIED);
  if (!Sprocedurep(callback))
    return MakeErrorPair("osi::StepStatement", ERROR_BAD_ARGUMENTS);
  return StartWorker(new Stepper(ste.stmt, ste.db_handle, callback));
}

ptr osi::GetSQLiteStatus(int operation, bool reset)
{
  int current;
  int highwater;
  int rc = sqlite3_status(operation, &current, &highwater, reset);
  if (SQLITE_OK != rc)
    return MakeSQLiteErrorPair("sqlite3_status", rc);
  ptr v = Smake_vector(2, Sfixnum(0));
  Svector_set(v, 0, Sinteger(current));
  Svector_set(v, 1, Sinteger(highwater));
  return v;
}
