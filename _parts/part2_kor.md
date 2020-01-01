---
title: 제2 장 - 세상에서 가장 간단한 SQL 컴파일러 및 가상 머신
date: 2017-08-31
---

sqlite를 본뜨는 작업을 진행 중입니다. sqlite의 전단 부는 문자열을 구문 분석하여 내부 표현 형태인 바이트코드로 출력하는 SQL 컴파일러입니다.

이 바이트 코드는 가상 머신으로 전달되고, 가상 머신은 바이트코드를 실행합니다.

{% include image.html url="assets/images/arch2.gif" description="SQLite 구조 (https://www.sqlite.org/arch.html)" %}

두 단계로 나누는 것은 두 가지 이점을 갖습니다.
- 각 부분의 복잡성을 낮추게 됩니다. (예: 가상 머신은 구문 오류를 고려하지 않아도 됩니다.)
- 자주 쓰이는 쿼리를 컴파일하고 바이트코드를 캐싱 하여 성능을 향상시킬 수 있습니다.

이를 염두에 두고, `main` 함수를 리팩토링하고 두 가지 새로운 키워드를 추가해보겠습니다:

```diff
 int main(int argc, char* argv[]) {
   InputBuffer* input_buffer = new_input_buffer();
   while (true) {
     print_prompt();
     read_input(input_buffer);

-    if (strcmp(input_buffer->buffer, ".exit") == 0) {
-      exit(EXIT_SUCCESS);
-    } else {
-      printf("Unrecognized command '%s'.\n", input_buffer->buffer);
+    if (input_buffer->buffer[0] == '.') {
+      switch (do_meta_command(input_buffer)) {
+        case (META_COMMAND_SUCCESS):
+          continue;
+        case (META_COMMAND_UNRECOGNIZED_COMMAND):
+          printf("Unrecognized command '%s'\n", input_buffer->buffer);
+          continue;
+      }
     }
+
+    Statement statement;
+    switch (prepare_statement(input_buffer, &statement)) {
+      case (PREPARE_SUCCESS):
+        break;
+      case (PREPARE_UNRECOGNIZED_STATEMENT):
+        printf("Unrecognized keyword at start of '%s'.\n",
+               input_buffer->buffer);
+        continue;
+    }
+
+    execute_statement(&statement);
+    printf("Executed.\n");
   }
 }
```

`.exit` 와 같은 Non-SQL 문장들은 "메타 명령(meta-commands)" 이라고 합니다. 모든 메타 명령은 점으로 시작하므로, 점을 검사하고 처리하는 작업을 별도의 함수로 만듭니다.

다음으로, 입력받은 문장을 우리의 내부 표현 형태로 변환하는 단계를 추가합니다. 이것은 우리의 sqlite 전단부의 임시 버전입니다.

마지막으로 준비된 문장을 `execute_statement` 함수에 전달합니다. 최종적으로 이 함수는 우리의 가상 머신이 될 것입니다.

두 개의 새로운 함수들은 성공 혹은 실패의 열거형을 반환하는 것을 유의하시기 바랍니다:

```c
typedef enum {
  META_COMMAND_SUCCESS,
  META_COMMAND_UNRECOGNIZED_COMMAND
} MetaCommandResult;

typedef enum { PREPARE_SUCCESS, PREPARE_UNRECOGNIZED_STATEMENT } PrepareResult;
```

"인식되지 못한 문장(Unrecognized statement)"은 예외 처리를 위한 것처럼 보일 수 있습니다. 그러나 [예외 처리는 좋지 않습니다.](https://www.youtube.com/watch?v=EVhCUSgNbzo) (심지어 C는 지원하지 않습니다.) 그래서, 필자는 가능한 열거형 결과 코드를 사용하여 처리합니다. switch 문이 열거 형 멤버를 처리하지 않으면 C 컴파일러가 문제를 제기하므로 우리는 함수의 모든 결과를 처리하고 있음을 확신할 수 있습니다. 앞으로 더 많은 결과 코드가 추가될 것입니다.

`do_meta_command` 는 기존 기능을 단순히 감싼 함수로, 더 많은 명령들의 확장에 열려있습니다.

```c
MetaCommandResult do_meta_command(InputBuffer* input_buffer) {
  if (strcmp(input_buffer->buffer, ".exit") == 0) {
    exit(EXIT_SUCCESS);
  } else {
    return META_COMMAND_UNRECOGNIZED_COMMAND;
  }
}
```

현재 "준비된 문장(prepared statement)" 은 두 가지 멤버 값을 갖는 열거형을 갖고 있습니다. 추후에, 매개 변수를 허용함에 따라 더 많은 데이터를 갖게 될 것입니다.

```c
typedef enum { STATEMENT_INSERT, STATEMENT_SELECT } StatementType;

typedef struct {
  StatementType type;
} Statement;
```

현재 `prepare_statement` (우리의 "SQL 컴파일러")는 SQL을 이해하지 못합니다. 정확하게는 두 단어만을 이해합니다.
```c
PrepareResult prepare_statement(InputBuffer* input_buffer,
                                Statement* statement) {
  if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
    statement->type = STATEMENT_INSERT;
    return PREPARE_SUCCESS;
  }
  if (strcmp(input_buffer->buffer, "select") == 0) {
    statement->type = STATEMENT_SELECT;
    return PREPARE_SUCCESS;
  }

  return PREPARE_UNRECOGNIZED_STATEMENT;
}
```

"insert" 키워드 뒤에 데이터가 있으므로 `strncmp` 를 사용한다는 점을 유의하시기 바랍니다. (예: `insert 1 cstack foo@bar.com`)

마지막으로 `execute_statement`는 몇 가지 스텁을 갖습니다.
```c
void execute_statement(Statement* statement) {
  switch (statement->type) {
    case (STATEMENT_INSERT):
      printf("This is where we would do an insert.\n");
      break;
    case (STATEMENT_SELECT):
      printf("This is where we would do a select.\n");
      break;
  }
}
```

아직 잘못될 부분이 없기 때문에 어떠한 오류 코드도 반환되지 않음을 유의하시기 바랍니다.

개선 작업을 통해 두 개의 키워드를 인식하게 되었습니다!
```command-line
~ ./db
db > insert foo bar
This is where we would do an insert.
Executed.
db > delete foo
Unrecognized keyword at start of 'delete foo'.
db > select
This is where we would do a select.
Executed.
db > .tables
Unrecognized command '.tables'
db > .exit
~
```

데이터베이스가 모형을 갖춰가고 있습니다... 데이터를 저장하면 더 좋지 않을까요? 다음 장에서는 `insert` 와 `select` 를 구현하며, 최악의 데이터 저장소를 만들어볼 것입니다. 지금 까지 바뀐 부분을 다음과 같습니다.

```diff
@@ -10,6 +10,23 @@ struct InputBuffer_t {
 } InputBuffer;
 
+typedef enum {
+  META_COMMAND_SUCCESS,
+  META_COMMAND_UNRECOGNIZED_COMMAND
+} MetaCommandResult;
+
+typedef enum { PREPARE_SUCCESS, PREPARE_UNRECOGNIZED_STATEMENT } PrepareResult;
+
+typedef enum { STATEMENT_INSERT, STATEMENT_SELECT } StatementType;
+
+typedef struct {
+  StatementType type;
+} Statement;
+
 InputBuffer* new_input_buffer() {
   InputBuffer* input_buffer = malloc(sizeof(InputBuffer));
   input_buffer->buffer = NULL;
@@ -40,17 +57,67 @@ void close_input_buffer(InputBuffer* input_buffer) {
     free(input_buffer);
 }
 
+MetaCommandResult do_meta_command(InputBuffer* input_buffer) {
+  if (strcmp(input_buffer->buffer, ".exit") == 0) {
+    close_input_buffer(input_buffer);
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
+void execute_statement(Statement* statement) {
+  switch (statement->type) {
+    case (STATEMENT_INSERT):
+      printf("This is where we would do an insert.\n");
+      break;
+    case (STATEMENT_SELECT):
+      printf("This is where we would do a select.\n");
+      break;
+  }
+}
+
 int main(int argc, char* argv[]) {
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
+      switch (do_meta_command(input_buffer)) {
+        case (META_COMMAND_SUCCESS):
+          continue;
+        case (META_COMMAND_UNRECOGNIZED_COMMAND):
+          printf("Unrecognized command '%s'\n", input_buffer->buffer);
+          continue;
+      }
     }
+
+    Statement statement;
+    switch (prepare_statement(input_buffer, &statement)) {
+      case (PREPARE_SUCCESS):
+        break;
+      case (PREPARE_UNRECOGNIZED_STATEMENT):
+        printf("Unrecognized keyword at start of '%s'.\n",
+               input_buffer->buffer);
+        continue;
+    }
+
+    execute_statement(&statement);
+    printf("Executed.\n");
   }
 }
```
