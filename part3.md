# Part 3 - An In-Memory, Append-Only, Single-Table Database

We're going to start small by putting a lot of limitations on our database. For now, it will:

- support two operations: inserting a row and printing all rows
- reside only in memory (no persistance to disk)
- support a single, hard-coded table

Our hard-coded table is going to store users and look like this:

| column   | type         |
|----------|--------------|
| id       | integer      |
| username | varchar(32)  |
| email    | varchar(255) |

This is a simple schema, but it gets us to support multiple data types and multiple sizes of text data types.

`insert` statements are now going to look like this:

```
insert 1 cstack foo@bar.com
```

That means we need to upgrade our `prepare_statement` function to parse arguments

```diff
   if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
     statement->type = STATEMENT_INSERT;
+    int args_assigned = sscanf(
+        input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
+        statement->row_to_insert.username, statement->row_to_insert.email);
+    if (args_assigned < 3) {
+      return PREPARE_SYNTAX_ERROR;
+    }
     return PREPARE_SUCCESS;
   }
   if (strcmp(input_buffer->buffer, "select") == 0) {
```

We store those parsed arguments into a new `Row` data structure inside the statement object:

```diff
+const uint32_t COLUMN_USERNAME_SIZE = 32;
+const uint32_t COLUMN_EMAIL_SIZE = 255;
+struct Row_t {
+  uint32_t id;
+  char username[COLUMN_USERNAME_SIZE];
+  char email[COLUMN_EMAIL_SIZE];
+};
+typedef struct Row_t Row;
+
 struct Statement_t {
   StatementType type;
+  Row row_to_insert;  // only used by insert statement
 };
 typedef struct Statement_t Statement;
```

Now we need to copy that data into some data structure representing the table. SQLite uses a B-tree for fast lookups, inserts and deletes. But we'll start with something simpler: an array.

There's no way for the database to know up-front how much space it needs, so we'll need to dynamically allocate memory. But allocating separate memory for each row would result in a lot of overhead storing pointers from one node to the next. It would also make saving the data structure to a file harder. Here's my alternative:

- Store rows in blocks of memory called pages
- Each page stores as many rows as it can fit
- Rows are serialized into a compact representation with each page
- Pages are only allocated as needed
- Keep a fixed-size array of pointers to pages so a row at index `i` can be found in constant time

First, the code to convert rows to and from their compact representation:
```diff
+const uint32_t ID_SIZE = sizeof(((Row*)0)->id);
+const uint32_t USERNAME_SIZE = sizeof(((Row*)0)->username);
+const uint32_t EMAIL_SIZE = sizeof(((Row*)0)->email);
+const uint32_t ID_OFFSET = 0;
+const uint32_t USERNAME_OFFSET = ID_OFFSET + ID_SIZE;
+const uint32_t EMAIL_OFFSET = USERNAME_OFFSET + USERNAME_SIZE;
+const uint32_t ROW_SIZE = ID_SIZE + USERNAME_SIZE + EMAIL_SIZE;
```
```diff
+void serialize_row(Row* source, void* destination) {
+  memcpy(destination + ID_OFFSET, &(source->id), ID_SIZE);
+  memcpy(destination + USERNAME_OFFSET, &(source->username), USERNAME_SIZE);
+  memcpy(destination + EMAIL_OFFSET, &(source->email), EMAIL_SIZE);
+}
+
+void deserialize_row(void* source, Row* destination) {
+  memcpy(&(destination->id), source + ID_OFFSET, ID_SIZE);
+  memcpy(&(destination->username), source + USERNAME_OFFSET, USERNAME_SIZE);
+  memcpy(&(destination->email), source + EMAIL_OFFSET, EMAIL_SIZE);
+}
```

Next, a Table structure that points to pages of rows and keeps track of how many rows there are:
```diff
+const uint32_t PAGE_SIZE = 4096;
+const uint32_t TABLE_MAX_PAGES = 100;
+const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
+const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
+
+struct Table_t {
+  void* pages[TABLE_MAX_PAGES];
+  uint32_t num_rows;
+};
+typedef struct Table_t Table;
```

And a way to find where in memory a particular row should go:
```diff
+void* row_slot(Table* table, uint32_t row_num) {
+  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  void* page = table->pages[page_num];
+  if (!page) {
+    // Allocate memory only when we try to access page
+    page = table->pages[page_num] = malloc(PAGE_SIZE);
+  }
+  uint32_t row_offset = row_num % ROWS_PER_PAGE;
+  uint32_t byte_offset = row_offset * ROW_SIZE;
+  return page + byte_offset;
+}
```

Now we can make `execute_statement` read/write from our table structure:
```diff
-void execute_statement(Statement* statement) {
+ExecuteResult execute_insert(Statement* statement, Table* table) {
+  if (table->num_rows >= TABLE_MAX_ROWS) {
+    return EXECUTE_TABLE_FULL;
+  }
+
+  Row* row_to_insert = &(statement->row_to_insert);
+
+  serialize_row(row_to_insert, row_slot(table, table->num_rows));
+  table->num_rows += 1;
+
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_select(Statement* statement, Table* table) {
+  Row row;
+  for (uint32_t i = 0; i < table->num_rows; i++) {
+    deserialize_row(row_slot(table, i), &row);
+    print_row(&row);
+  }
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_statement(Statement* statement, Table* table) {
   switch (statement->type) {
     case (STATEMENT_INSERT):
-      printf("This is where we would do an insert.\n");
-      break;
+      return execute_insert(statement, table);
     case (STATEMENT_SELECT):
-      printf("This is where we would do a select.\n");
-      break;
+      return execute_select(statement, table);
   }
 }
```

Lastly, we need to initialize the table and handle a few more error cases:

```diff
+ Table* new_table() {
+  Table* table = malloc(sizeof(Table));
+  table->num_rows = 0;
+
+  return table;
+}
```
```diff
 int main(int argc, char* argv[]) {
+  Table* table = new_table();
   InputBuffer* input_buffer = new_input_buffer();
   while (true) {
     print_prompt();
@@ -105,13 +203,22 @@ int main(int argc, char* argv[]) {
     switch (prepare_statement(input_buffer, &statement)) {
       case (PREPARE_SUCCESS):
         break;
+      case (PREPARE_SYNTAX_ERROR):
+        printf("Syntax error. Could not parse statement.\n");
+        continue;
       case (PREPARE_UNRECOGNIZED_STATEMENT):
         printf("Unrecognized keyword at start of '%s'.\n",
                input_buffer->buffer);
         continue;
     }

-    execute_statement(&statement);
-    printf("Executed.\n");
+    switch (execute_statement(&statement, table)) {
+      case (PREPARE_SUCCESS):
+        printf("Executed.\n");
+        break;
+      case (EXECUTE_TABLE_FULL):
+        printf("Error: Table full.\n");
+        break;
+    }
   }
 }
 ```

 With those changes we can actually save data in our database!
 ```command-line
~ ./db
db > insert 1 cstack foo@bar.com
Executed.
db > insert 2 bob bob@example.com
Executed.
db > select
(1, cstack, foo@bar.com)
(2, bob, bob@example.com)
Executed.
db > insert foo bar 1
Syntax error. Could not parse statement.
db > .exit
~
```

Now would be a great time to write some tests, for a couple reasons:
- We're planning to dramatically change the data structure storing our table, and tests would catch regressions.
- There are a couple edge cases we haven't tested manually (e.g. filling up the table)

We'll address those issues in Part 4. For now, here's the complete diff from this part:
```diff
@@ -10,23 +10,94 @@ struct InputBuffer_t {
 };
 typedef struct InputBuffer_t InputBuffer;
 
+enum ExecuteResult_t { EXECUTE_SUCCESS, EXECUTE_TABLE_FULL };
+typedef enum ExecuteResult_t ExecuteResult;
+
 enum MetaCommandResult_t {
   META_COMMAND_SUCCESS,
   META_COMMAND_UNRECOGNIZED_COMMAND
 };
 typedef enum MetaCommandResult_t MetaCommandResult;
 
-enum PrepareResult_t { PREPARE_SUCCESS, PREPARE_UNRECOGNIZED_STATEMENT };
+enum PrepareResult_t {
+  PREPARE_SUCCESS,
+  PREPARE_SYNTAX_ERROR,
+  PREPARE_UNRECOGNIZED_STATEMENT
+};
 typedef enum PrepareResult_t PrepareResult;
 
 enum StatementType_t { STATEMENT_INSERT, STATEMENT_SELECT };
 typedef enum StatementType_t StatementType;
 
+const uint32_t COLUMN_USERNAME_SIZE = 32;
+const uint32_t COLUMN_EMAIL_SIZE = 255;
+struct Row_t {
+  uint32_t id;
+  char username[COLUMN_USERNAME_SIZE];
+  char email[COLUMN_EMAIL_SIZE];
+};
+typedef struct Row_t Row;
+
 struct Statement_t {
   StatementType type;
+  Row row_to_insert;  // only used by insert statement
 };
 typedef struct Statement_t Statement;
 
+const uint32_t ID_SIZE = sizeof(((Row*)0)->id);
+const uint32_t USERNAME_SIZE = sizeof(((Row*)0)->username);
+const uint32_t EMAIL_SIZE = sizeof(((Row*)0)->email);
+const uint32_t ID_OFFSET = 0;
+const uint32_t USERNAME_OFFSET = ID_OFFSET + ID_SIZE;
+const uint32_t EMAIL_OFFSET = USERNAME_OFFSET + USERNAME_SIZE;
+const uint32_t ROW_SIZE = ID_SIZE + USERNAME_SIZE + EMAIL_SIZE;
+
+const uint32_t PAGE_SIZE = 4096;
+const uint32_t TABLE_MAX_PAGES = 100;
+const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
+const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
+
+struct Table_t {
+  void* pages[TABLE_MAX_PAGES];
+  uint32_t num_rows;
+};
+typedef struct Table_t Table;
+
+void print_row(Row* row) {
+  printf("(%d, %s, %s)\n", row->id, row->username, row->email);
+}
+
+void serialize_row(Row* source, void* destination) {
+  memcpy(destination + ID_OFFSET, &(source->id), ID_SIZE);
+  memcpy(destination + USERNAME_OFFSET, &(source->username), USERNAME_SIZE);
+  memcpy(destination + EMAIL_OFFSET, &(source->email), EMAIL_SIZE);
+}
+
+void deserialize_row(void* source, Row* destination) {
+  memcpy(&(destination->id), source + ID_OFFSET, ID_SIZE);
+  memcpy(&(destination->username), source + USERNAME_OFFSET, USERNAME_SIZE);
+  memcpy(&(destination->email), source + EMAIL_OFFSET, EMAIL_SIZE);
+}
+
+void* row_slot(Table* table, uint32_t row_num) {
+  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  void* page = table->pages[page_num];
+  if (!page) {
+    // Allocate memory only when we try to access page
+    page = table->pages[page_num] = malloc(PAGE_SIZE);
+  }
+  uint32_t row_offset = row_num % ROWS_PER_PAGE;
+  uint32_t byte_offset = row_offset * ROW_SIZE;
+  return page + byte_offset;
+}
+
+Table* new_table() {
+  Table* table = malloc(sizeof(Table));
+  table->num_rows = 0;
+
+  return table;
+}
+
 InputBuffer* new_input_buffer() {
   InputBuffer* input_buffer = malloc(sizeof(InputBuffer));
   input_buffer->buffer = NULL;
@@ -64,6 +135,12 @@ PrepareResult prepare_statement(InputBuffer* input_buffer,
                                 Statement* statement) {
   if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
     statement->type = STATEMENT_INSERT;
+    int args_assigned = sscanf(
+        input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
+        statement->row_to_insert.username, statement->row_to_insert.email);
+    if (args_assigned < 3) {
+      return PREPARE_SYNTAX_ERROR;
+    }
     return PREPARE_SUCCESS;
   }
   if (strcmp(input_buffer->buffer, "select") == 0) {
@@ -74,18 +151,39 @@ PrepareResult prepare_statement(InputBuffer* input_buffer,
   return PREPARE_UNRECOGNIZED_STATEMENT;
 }
 
-void execute_statement(Statement* statement) {
+ExecuteResult execute_insert(Statement* statement, Table* table) {
+  if (table->num_rows >= TABLE_MAX_ROWS) {
+    return EXECUTE_TABLE_FULL;
+  }
+
+  Row* row_to_insert = &(statement->row_to_insert);
+
+  serialize_row(row_to_insert, row_slot(table, table->num_rows));
+  table->num_rows += 1;
+
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_select(Statement* statement, Table* table) {
+  Row row;
+  for (uint32_t i = 0; i < table->num_rows; i++) {
+    deserialize_row(row_slot(table, i), &row);
+    print_row(&row);
+  }
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_statement(Statement* statement, Table* table) {
   switch (statement->type) {
     case (STATEMENT_INSERT):
-      printf("This is where we would do an insert.\n");
-      break;
+      return execute_insert(statement, table);
     case (STATEMENT_SELECT):
-      printf("This is where we would do a select.\n");
-      break;
+      return execute_select(statement, table);
   }
 }
 
 int main(int argc, char* argv[]) {
+  Table* table = new_table();
   InputBuffer* input_buffer = new_input_buffer();
   while (true) {
     print_prompt();
@@ -105,13 +203,22 @@ int main(int argc, char* argv[]) {
     switch (prepare_statement(input_buffer, &statement)) {
       case (PREPARE_SUCCESS):
         break;
+      case (PREPARE_SYNTAX_ERROR):
+        printf("Syntax error. Could not parse statement.\n");
+        continue;
       case (PREPARE_UNRECOGNIZED_STATEMENT):
         printf("Unrecognized keyword at start of '%s'.\n",
                input_buffer->buffer);
         continue;
     }
 
-    execute_statement(&statement);
-    printf("Executed.\n");
+    switch (execute_statement(&statement, table)) {
+      case (PREPARE_SUCCESS):
+        printf("Executed.\n");
+        break;
+      case (EXECUTE_TABLE_FULL):
+        printf("Error: Table full.\n");
+        break;
+    }
   }
 }
```