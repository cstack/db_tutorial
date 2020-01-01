---
title: 제3 장 - 메모리 내, 추가 전용, 단일 테이블 데이터베이스
date: 2017-09-01
---

데이터베이스에 많은 제한을 두어, 작은 규모로 시작해 보겠습니다. 우선, 다음과 같은 제한을 두겠습니다.

- 두 가지 연산 만 지원: 행 삽입 및 모든 행 출력
- 메모리에만 존재 (디스크에 지속 보존되지 않음) 
- 하드 코딩 된 단일 테이블만 지원

하드 코딩 된 테이블은 사용자를 저장할 것이며, 형태는 다음과 같습니다.

| column   | type         |
|----------|--------------|
| id       | integer      |
| username | varchar(32)  |
| email    | varchar(255) |

단순한 스키마이지만, 여러 데이터 타입과 다양한 크기의 텍스트 데이터 타입을 지원합니다.

`insert` 문은 다음과 같습니다.

```
insert 1 cstack foo@bar.com
```

즉, 입력 인자들을 파싱 할 수 있도록  `prepare_statement` 함수를 개선해야 합니다.

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

파싱 된 입력 인자들은 새로운 `Row` 데이터 구조체 형태로 statement 객체 내부에 저장됩니다.

```diff
+#define COLUMN_USERNAME_SIZE 32
+#define COLUMN_EMAIL_SIZE 255
+typedef struct {
+  uint32_t id;
+  char username[COLUMN_USERNAME_SIZE];
+  char email[COLUMN_EMAIL_SIZE];
+} Row;
+
 typedef struct {
   StatementType type;
+  Row row_to_insert;  // insert 문에서만 사용됩니다.
 } Statement;
```

이제 입력 데이터를 테이블을 표현하는 데이터 구조로 복사할 필요가 있습니다. SQLite의 경우 빠른 조회, 삽입 및 삭제를 위해 B-트리를 사용합니다. 우리는 좀 더 간단한 데이터 구조를 사용하여 진행하겠습니다. B-트리와 마찬가지로, 행을 페이지로 그룹화하지만, 페이지들을 트리 형태가 아닌 배열 형태로 처리하겠습니다.

계획은 다음과 같습니다.

- 페이지라는 메모리 블록에 행을 저장합니다.
- 각 페이지는 최대한 많은 행을 저장합니다.
- 각 페이지에 행들은 촘촘한 표현 형태로 직렬화되어 저장됩니다.
- 페이지는 필요한 경우에만 할당됩니다.
- 페이지는 고정 크기의 포인터 배열로 관리됩니다.

먼저 행의 촘촘한 표현 형태를 정의합니다.
```diff
+#define size_of_attribute(Struct, Attribute) sizeof(((Struct*)0)->Attribute)
+
+const uint32_t ID_SIZE = size_of_attribute(Row, id);
+const uint32_t USERNAME_SIZE = size_of_attribute(Row, username);
+const uint32_t EMAIL_SIZE = size_of_attribute(Row, email);
+const uint32_t ID_OFFSET = 0;
+const uint32_t USERNAME_OFFSET = ID_OFFSET + ID_SIZE;
+const uint32_t EMAIL_OFFSET = USERNAME_OFFSET + USERNAME_SIZE;
+const uint32_t ROW_SIZE = ID_SIZE + USERNAME_SIZE + EMAIL_SIZE;
```

즉, 직렬화된 행의 형태는 다음과 같습니다. 

| column   | size (bytes) | offset       |
|----------|--------------|--------------|
| id       | 4            | 0            |
| username | 32           | 4            |
| email    | 255          | 36           |
| total    | 291          |              |

촘촘한 표현 형태로 변환하거나 재변환하는 코드도 필요합니다.
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

다음은 행의 페이지들을 가리키고 행의 수를 추적관리하는 `Table` 구조체입니다.
```diff
+const uint32_t PAGE_SIZE = 4096;
+#define TABLE_MAX_PAGES 100
+const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
+const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
+
+typedef struct {
+  uint32_t num_rows;
+  void* pages[TABLE_MAX_PAGES];
+} Table;
```

페이지 크기는 대부분의 컴퓨터 구조들이 가상 메모리 시스템에서 사용하는 것과 같은 4 킬로바이트로 만들었습니다. 이점은 우리 데이터베이스의 한 페이지가 운영체제의 한 페이지에 해당함을 의미합니다. 따라서, 운영체제는 페이지를 분할하지 않고 페이지를 메모리 내외로 이동시킬 것입니다.

100페이지 할당 제한은 임의로 설정 한 것입니다. 트리구조로 전환하게 되면 데이터베이스의 최대 크기는 파일 최대 크기에 의해서만 제한될 것입니다. (한 번에 메모리에 보관하는 페이지 수는 제한이 될 것입니다.)

행은 페이지 경계를 넘지 않아야 합니다. 페이지가 메모리에 연속적으로 존재하지 않기 때문에, 행을 좀 더 쉽게 읽고 쓸 수 있게 합니다.

말이 나온 김에, 다음은 읽고 쓸 행의 메모리 위치를 찾는 방법입니다. 
```diff
+void* row_slot(Table* table, uint32_t row_num) {
+  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  void* page = table->pages[page_num];
+  if (page == NULL) {
+    // 페이지에 접근하는 경우 메모리 할당
+    page = table->pages[page_num] = malloc(PAGE_SIZE);
+  }
+  uint32_t row_offset = row_num % ROWS_PER_PAGE;
+  uint32_t byte_offset = row_offset * ROW_SIZE;
+  return page + byte_offset;
+}
```

이제 `execute_statement` 함수에서 우리의 테이블 구조를 읽고 쓰도록 만들 수 있습니다.
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

마지막으로 테이블 초기화 및 메모리 해제 함수를 생성하고 몇 가지 에러 처리를 합니다.

```diff
+ Table* new_table() {
+  Table* table = malloc(sizeof(Table));
+  table->num_rows = 0;
+  for (uint32_t i = 0; i < TABLE_MAX_PAGES; i++) {
+     table->pages[i] = NULL;
+  }
+  return table;
+}
+
+void free_table(Table* table) {
+    for (int i = 0; table->pages[i]; i++) {
+	free(table->pages[i]);
+    }
+    free(table);
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
+      case (EXECUTE_SUCCESS):
+        printf("Executed.\n");
+        break;
+      case (EXECUTE_TABLE_FULL):
+        printf("Error: Table full.\n");
+        break;
+    }
   }
 }
 ```

 변경을 통해 데이터베이스에 데이터를 저장할 수 있게 되었습니다!
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

이쯤에서, 테스트를 수행해보는 것이 좋을 것 같습니다. 여기서 테스트를 수행하는 것에는 몇 가지 이유가 있습니다. 
- 앞으로 테이블에 저장되는 데이터 구조를 극적으로 변경할 것이며, 테스트를 통해 회귀 테스트 케이스를 얻는 것이 큰 도움이 될 것입니다.
- 수동으로 테스트하지 못할 몇 가지 엣지 케이스가 존재합니다. (예: 테이블 가득 채우기)

다음 장에서 이 사항들을 다루어 보겠습니다. 지금까지 변경된 부분은 다음과 같습니다.
```diff
@@ -2,6 +2,7 @@
 #include <stdio.h>
 #include <stdlib.h>
 #include <string.h>
+#include <stdint.h>

 typedef struct {
   char* buffer;
@@ -10,6 +11,105 @@ typedef struct {
 } InputBuffer;

+typedef enum { EXECUTE_SUCCESS, EXECUTE_TABLE_FULL } ExecuteResult;
+
+typedef enum {
+  META_COMMAND_SUCCESS,
+  META_COMMAND_UNRECOGNIZED_COMMAND
+} MetaCommandResult;
+
+typedef enum {
+  PREPARE_SUCCESS,
+  PREPARE_SYNTAX_ERROR,
+  PREPARE_UNRECOGNIZED_STATEMENT
+ } PrepareResult;
+
+typedef enum { STATEMENT_INSERT, STATEMENT_SELECT } StatementType;
+
+#define COLUMN_USERNAME_SIZE 32
+#define COLUMN_EMAIL_SIZE 255
+typedef struct {
+  uint32_t id;
+  char username[COLUMN_USERNAME_SIZE];
+  char email[COLUMN_EMAIL_SIZE];
+} Row;
+
+typedef struct {
+  StatementType type;
+  Row row_to_insert; // insert 문에서만 사용됩니다.
+} Statement;
+
+#define size_of_attribute(Struct, Attribute) sizeof(((Struct*)0)->Attribute)
+
+const uint32_t ID_SIZE = size_of_attribute(Row, id);
+const uint32_t USERNAME_SIZE = size_of_attribute(Row, username);
+const uint32_t EMAIL_SIZE = size_of_attribute(Row, email);
+const uint32_t ID_OFFSET = 0;
+const uint32_t USERNAME_OFFSET = ID_OFFSET + ID_SIZE;
+const uint32_t EMAIL_OFFSET = USERNAME_OFFSET + USERNAME_SIZE;
+const uint32_t ROW_SIZE = ID_SIZE + USERNAME_SIZE + EMAIL_SIZE;
+
+const uint32_t PAGE_SIZE = 4096;
+#define TABLE_MAX_PAGES 100
+const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
+const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
+
+typedef struct {
+  uint32_t num_rows;
+  void* pages[TABLE_MAX_PAGES];
+} Table;
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
+void deserialize_row(void *source, Row* destination) {
+  memcpy(&(destination->id), source + ID_OFFSET, ID_SIZE);
+  memcpy(&(destination->username), source + USERNAME_OFFSET, USERNAME_SIZE);
+  memcpy(&(destination->email), source + EMAIL_OFFSET, EMAIL_SIZE);
+}
+
+void* row_slot(Table* table, uint32_t row_num) {
+  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  void *page = table->pages[page_num];
+  if (page == NULL) {
+     // 페이지에 접근하는 경우 메모리 할당
+     page = table->pages[page_num] = malloc(PAGE_SIZE);
+  }
+  uint32_t row_offset = row_num % ROWS_PER_PAGE;
+  uint32_t byte_offset = row_offset * ROW_SIZE;
+  return page + byte_offset;
+}
+
+Table* new_table() {
+  Table* table = malloc(sizeof(Table));
+  table->num_rows = 0;
+  for (uint32_t i = 0; i < TABLE_MAX_PAGES; i++) {
+     table->pages[i] = NULL;
+  }
+  return table;
+}
+
+void free_table(Table* table) {
+  for (int i = 0; table->pages[i]; i++) {
+     free(table->pages[i]);
+  }
+  free(table);
+}
+
 InputBuffer* new_input_buffer() {
   InputBuffer* input_buffer = malloc(sizeof(InputBuffer));
   input_buffer->buffer = NULL;
@@ -40,17 +140,105 @@ void close_input_buffer(InputBuffer* input_buffer) {
     free(input_buffer);
 }

+MetaCommandResult do_meta_command(InputBuffer* input_buffer, Table *table) {
+  if (strcmp(input_buffer->buffer, ".exit") == 0) {
+    close_input_buffer(input_buffer);
+    free_table(table);
+    exit(EXIT_SUCCESS);
+  } else {
+    return META_COMMAND_UNRECOGNIZED_COMMAND;
+  }
+}
+
+PrepareResult prepare_statement(InputBuffer* input_buffer,
+                                Statement* statement) {
+  if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
+    statement->type = STATEMENT_INSERT;
+    int args_assigned = sscanf(
+	input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
+	statement->row_to_insert.username, statement->row_to_insert.email
+	);
+    if (args_assigned < 3) {
+	return PREPARE_SYNTAX_ERROR;
+    }
+    return PREPARE_SUCCESS;
+  }
+  if (strcmp(input_buffer->buffer, "select") == 0) {
+    statement->type = STATEMENT_SELECT;
+    return PREPARE_SUCCESS;
+  }
+
+  return PREPARE_UNRECOGNIZED_STATEMENT;
+}
+
+ExecuteResult execute_insert(Statement* statement, Table* table) {
+  if (table->num_rows >= TABLE_MAX_ROWS) {
+     return EXECUTE_TABLE_FULL;
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
+     deserialize_row(row_slot(table, i), &row);
+     print_row(&row);
+  }
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_statement(Statement* statement, Table *table) {
+  switch (statement->type) {
+    case (STATEMENT_INSERT):
+       	return execute_insert(statement, table);
+    case (STATEMENT_SELECT):
+	return execute_select(statement, table);
+  }
+}
+
 int main(int argc, char* argv[]) {
+  Table* table = new_table();
   InputBuffer* input_buffer = new_input_buffer();
   while (true) {
     print_prompt();
     read_input(input_buffer);

-    if (strcmp(input_buffer->buffer, ".exit") == 0) {
-      close_input_buffer(input_buffer);
-      exit(EXIT_SUCCESS);
-    } else {
-      printf("Unrecognized command '%s'.\n", input_buffer->buffer);
+    if (input_buffer->buffer[0] == '.') {
+      switch (do_meta_command(input_buffer, table)) {
+        case (META_COMMAND_SUCCESS):
+          continue;
+        case (META_COMMAND_UNRECOGNIZED_COMMAND):
+          printf("Unrecognized command '%s'\n", input_buffer->buffer);
+          continue;
+      }
+    }
+
+    Statement statement;
+    switch (prepare_statement(input_buffer, &statement)) {
+      case (PREPARE_SUCCESS):
+        break;
+      case (PREPARE_SYNTAX_ERROR):
+	printf("Syntax error. Could not parse statement.\n");
+	continue;
+      case (PREPARE_UNRECOGNIZED_STATEMENT):
+        printf("Unrecognized keyword at start of '%s'.\n",
+               input_buffer->buffer);
+        continue;
+    }
+
+    switch (execute_statement(&statement, table)) {
+	case (EXECUTE_SUCCESS):
+	    printf("Executed.\n");
+	    break;
+	case (EXECUTE_TABLE_FULL):
+	    printf("Error: Table full.\n");
+	    break;
     }
   }
 }
```
