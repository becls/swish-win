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

void sqlite_init();

namespace osi
{
  ptr OpenDatabase(ptr filename, int flags);
  ptr CloseDatabase(iptr database);
  ptr PrepareStatement(iptr database, ptr sql);
  ptr FinalizeStatement(iptr statement);
  ptr BindStatement(iptr statement, UINT index, ptr datum);
  ptr ClearStatementBindings(iptr statement);
  ptr GetLastInsertRowid(iptr database);
  ptr GetStatementColumns(iptr statement);
  ptr GetStatementSQL(iptr statement);
  ptr ResetStatement(iptr statement);
  ptr StepStatement(iptr statement, ptr callback);
  ptr GetSQLiteStatus(int operation, bool reset);
}

typedef struct
{
  sqlite3* db;
  bool busy;
} DatabaseEntry;

typedef HandleMap<DatabaseEntry, 32783> DatabaseMap;
extern DatabaseMap g_Databases;

typedef struct
{
  sqlite3_stmt* stmt;
  iptr db_handle;
} StatementEntry;

typedef HandleMap<StatementEntry, 32749> StatementMap;
extern StatementMap g_Statements;
