---
title: 제4 장 - 첫 테스트 (그리고 버그)
date: 2017-09-03
---

우리는 데이터베이스에 행을 삽입하고 모든 행을 출력해 볼 수 있게 되었습니다. 여기서, 지금까지 해온 것들을 테스트해보는 시간을 갖겠습니다.

필자가 사용에 익숙하기도 하며, 구문의 가독성도 좋은 [rspec](http://rspec.info/)을 사용하여 테스트를 진행하겠습니다.

먼저, 데이터베이스에 명령 목록을 보내도록 간단한 헬퍼를 정의하고 출력에 대한 어설션을 만듭니다.

```ruby
describe 'database' do
  def run_script(commands)
    raw_output = nil
    IO.popen("./db", "r+") do |pipe|
      commands.each do |command|
        pipe.puts command
      end

      pipe.close_write

      # Read entire output
      raw_output = pipe.gets(nil)
    end
    raw_output.split("\n")
  end

  it 'inserts and retreives a row' do
    result = run_script([
      "insert 1 user1 person1@example.com",
      "select",
      ".exit",
    ])
    expect(result).to match_array([
      "db > Executed.",
      "db > (1, user1, person1@example.com)",
      "Executed.",
      "db > ",
    ])
  end
end
```

이 간단한 테스트는 우리가 넣은 값이 제대로 출력됨을 확인 시켜 줄 것입니다. 그리고 제대로 작동하여 테스트를 통과합니다.

```command-line
bundle exec rspec
.

Finished in 0.00871 seconds (files took 0.09506 seconds to load)
1 example, 0 failures
```

이제 데이터베이스에 많은 수의 행을 삽입해보는 테스트가 가능해집니다.
```ruby
it 'prints error message when table is full' do
  script = (1..1401).map do |i|
    "insert #{i} user#{i} person#{i}@example.com"
  end
  script << ".exit"
  result = run_script(script)
  expect(result[-2]).to eq('db > Error: Table full.')
end
```

다시 테스트를 진행합니다...
```command-line
bundle exec rspec
..

Finished in 0.01553 seconds (files took 0.08156 seconds to load)
2 examples, 0 failures
```

잘 작동합니다! 최대 페이지 수가 100이며 각각 14 개의 행을 적재할 수 있으므로, 현재 우리의 데이터베이스는 1400개의 행을 보유할 수 있습니다.

지금까지 진행된 코드를 살펴보던 중, 텍스트 필드 저장을 제대로 처리하지 못함을 깨달았습니다. 다음 예제로 쉽게 테스트해볼 수 있습니다.
```ruby
it 'allows inserting strings that are the maximum length' do
  long_username = "a"*32
  long_email = "a"*255
  script = [
    "insert 1 #{long_username} #{long_email}",
    "select",
    ".exit",
  ]
  result = run_script(script)
  expect(result).to match_array([
    "db > Executed.",
    "db > (1, #{long_username}, #{long_email})",
    "Executed.",
    "db > ",
  ])
end
```

그리고 테스트는 실패합니다!
```ruby
Failures:

  1) database allows inserting strings that are the maximum length
     Failure/Error: raw_output.split("\n")

     ArgumentError:
       invalid byte sequence in UTF-8
     # ./spec/main_spec.rb:14:in `split'
     # ./spec/main_spec.rb:14:in `run_script'
     # ./spec/main_spec.rb:48:in `block (2 levels) in <top (required)>'
```

직접 실행해 보면, 행을 출력할 때 이상한 문자들이 있음을 알 수 있습니다. (긴 문자열은 줄여썼습니다.)
```command-line
db > insert 1 aaaaa... aaaaa...
Executed.
db > select
(1, aaaaa...aaa\�, aaaaa...aaa\�)
Executed.
db >
```

왜 그럴까요? 행의 정의를 보면, 이름에는 정확히 32 바이트, 이메일에는 255바이트를 할당한 것을 볼 수 있습니다. 그러나 [C 문자열](http://www.cprogramming.com/tutorial/c/lesson9.html) 은 공백으로 끝나게 되어있고, 우리는 공백을 위한 공간을 할당하지 않았습니다. 해결책은 한 바이트를 추가 할당하는 것입니다.
```diff
 const uint32_t COLUMN_EMAIL_SIZE = 255;
 typedef struct {
   uint32_t id;
-  char username[COLUMN_USERNAME_SIZE];
-  char email[COLUMN_EMAIL_SIZE];
+  char username[COLUMN_USERNAME_SIZE + 1];
+  char email[COLUMN_EMAIL_SIZE + 1];
 } Row;
 ```

 그리고 정말로 문제를 해결합니다.
 ```ruby
 bundle exec rspec
...

Finished in 0.0188 seconds (files took 0.08516 seconds to load)
3 examples, 0 failures
```

열 크기보다 긴 사용자 이름 또는 이메일을 삽입하는 것 역시 허용해서는 안 됩니다. 초과하는 케이스는 다음과 같습니다.
```ruby
it 'prints error message if strings are too long' do
  long_username = "a"*33
  long_email = "a"*256
  script = [
    "insert 1 #{long_username} #{long_email}",
    "select",
    ".exit",
  ]
  result = run_script(script)
  expect(result).to match_array([
    "db > String is too long.",
    "db > Executed.",
    "db > ",
  ])
end
```

초과를 방지하기 위해서는 파서를 개선해야 합니다. 참고로, 현재는 [scanf()](https://linux.die.net/man/3/scanf)를 사용하고 있습니다.
```c
if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
  statement->type = STATEMENT_INSERT;
  int args_assigned = sscanf(
      input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
      statement->row_to_insert.username, statement->row_to_insert.email);
  if (args_assigned < 3) {
    return PREPARE_SYNTAX_ERROR;
  }
  return PREPARE_SUCCESS;
}
```

그러나 [scanf는 몇 가지 약점이 있습니다.](https://stackoverflow.com/questions/2430303/disadvantages-of-scanf) scanf가 읽은 문자열이 입력 버퍼의 크기보다 큰 경우, 버퍼 오버플로우가 발생하여 예기치 않은 위치에 쓰기 작업을 수행합니다. 따라서, 우리는 `Row` 구조체에 각 문자열을 복사하기 전에, 길이를 확인해야 합니다. 이를 위해서는 입력을 공백으로 나눌 필요가 있습니다.

[strtok()](http://www.cplusplus.com/reference/cstring/strtok/)를 사용해서 하도록 하겠습니다. 실제로 보면 쉽게 이해할 수 있을 것입니다.

```diff
+PrepareResult prepare_insert(InputBuffer* input_buffer, Statement* statement) {
+  statement->type = STATEMENT_INSERT;
+
+  char* keyword = strtok(input_buffer->buffer, " ");
+  char* id_string = strtok(NULL, " ");
+  char* username = strtok(NULL, " ");
+  char* email = strtok(NULL, " ");
+
+  if (id_string == NULL || username == NULL || email == NULL) {
+    return PREPARE_SYNTAX_ERROR;
+  }
+
+  int id = atoi(id_string);
+  if (strlen(username) > COLUMN_USERNAME_SIZE) {
+    return PREPARE_STRING_TOO_LONG;
+  }
+  if (strlen(email) > COLUMN_EMAIL_SIZE) {
+    return PREPARE_STRING_TOO_LONG;
+  }
+
+  statement->row_to_insert.id = id;
+  strcpy(statement->row_to_insert.username, username);
+  strcpy(statement->row_to_insert.email, email);
+
+  return PREPARE_SUCCESS;
+}
+
 PrepareResult prepare_statement(InputBuffer* input_buffer,
                                 Statement* statement) {
   if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
+    return prepare_insert(input_buffer, statement);
-    statement->type = STATEMENT_INSERT;
-    int args_assigned = sscanf(
-        input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
-        statement->row_to_insert.username, statement->row_to_insert.email);
-    if (args_assigned < 3) {
-      return PREPARE_SYNTAX_ERROR;
-    }
-    return PREPARE_SUCCESS;
   }
```

연속적으로 `strtok` 를 호출하면 구분 문자(여기서는 공백에 해당)에 도달할 때마다 입력 버퍼에 null 문자를 삽입하여 하위 문자열로 분리합니다.

각 텍스트 값의 길이 초과 여부는 [strlen()](http://www.cplusplus.com/reference/cstring/strlen/)을 호출하여 확인할 수 있습니다.

다른 에러 코드와 마찬가지로 에러 처리를 할 수 있습니다.
```diff
 enum PrepareResult_t {
   PREPARE_SUCCESS,
+  PREPARE_STRING_TOO_LONG,
   PREPARE_SYNTAX_ERROR,
   PREPARE_UNRECOGNIZED_STATEMENT
 };
```
```diff
 switch (prepare_statement(input_buffer, &statement)) {
   case (PREPARE_SUCCESS):
     break;
+  case (PREPARE_STRING_TOO_LONG):
+    printf("String is too long.\n");
+    continue;
   case (PREPARE_SYNTAX_ERROR):
     printf("Syntax error. Could not parse statement.\n");
     continue;
```

파서 개선 작업은 테스트를 통과하게 만듭니다.
```command-line
bundle exec rspec
....

Finished in 0.02284 seconds (files took 0.116 seconds to load)
4 examples, 0 failures
```

하는 김에, 에러 케이스를 하나 더 처리하겠습니다.
```ruby
it 'prints an error message if id is negative' do
  script = [
    "insert -1 cstack foo@bar.com",
    "select",
    ".exit",
  ]
  result = run_script(script)
  expect(result).to match_array([
    "db > ID must be positive.",
    "db > Executed.",
    "db > ",
  ])
end
```
```diff
 enum PrepareResult_t {
   PREPARE_SUCCESS,
+  PREPARE_NEGATIVE_ID,
   PREPARE_STRING_TOO_LONG,
   PREPARE_SYNTAX_ERROR,
   PREPARE_UNRECOGNIZED_STATEMENT
@@ -148,9 +147,6 @@ PrepareResult prepare_insert(InputBuffer* input_buffer, Statement* statement) {
   }

   int id = atoi(id_string);
+  if (id < 0) {
+    return PREPARE_NEGATIVE_ID;
+  }
   if (strlen(username) > COLUMN_USERNAME_SIZE) {
     return PREPARE_STRING_TOO_LONG;
   }
@@ -230,9 +226,6 @@ int main(int argc, char* argv[]) {
     switch (prepare_statement(input_buffer, &statement)) {
       case (PREPARE_SUCCESS):
         break;
+      case (PREPARE_NEGATIVE_ID):
+        printf("ID must be positive.\n");
+        continue;
       case (PREPARE_STRING_TOO_LONG):
         printf("String is too long.\n");
         continue;
```

이제 테스트는 충분합니다. 다음 장은 매우 중요한 기능입니다. 지속성! 우리는 데이터 베이스를 파일에 저장하고 다시 읽어오도록 만들 것입니다.  

매우 근사한 작업이 될 것입니다.

지금까지 변경된 부분은 다음과 같습니다.
```diff
@@ -22,6 +22,8 @@

 enum PrepareResult_t {
   PREPARE_SUCCESS,
+  PREPARE_NEGATIVE_ID,
+  PREPARE_STRING_TOO_LONG,
   PREPARE_SYNTAX_ERROR,
   PREPARE_UNRECOGNIZED_STATEMENT
  };
@@ -34,8 +36,8 @@
 #define COLUMN_EMAIL_SIZE 255
 typedef struct {
   uint32_t id;
-  char username[COLUMN_USERNAME_SIZE];
-  char email[COLUMN_EMAIL_SIZE];
+  char username[COLUMN_USERNAME_SIZE + 1];
+  char email[COLUMN_EMAIL_SIZE + 1];
 } Row;

@@ -150,18 +152,40 @@ MetaCommandResult do_meta_command(InputBuffer* input_buffer, Table *table) {
   }
 }

-PrepareResult prepare_statement(InputBuffer* input_buffer,
-                                Statement* statement) {
-  if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
+PrepareResult prepare_insert(InputBuffer* input_buffer, Statement* statement) {
   statement->type = STATEMENT_INSERT;
-  int args_assigned = sscanf(
-     input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
-     statement->row_to_insert.username, statement->row_to_insert.email
-     );
-  if (args_assigned < 3) {
+
+  char* keyword = strtok(input_buffer->buffer, " ");
+  char* id_string = strtok(NULL, " ");
+  char* username = strtok(NULL, " ");
+  char* email = strtok(NULL, " ");
+
+  if (id_string == NULL || username == NULL || email == NULL) {
      return PREPARE_SYNTAX_ERROR;
   }
+
+  int id = atoi(id_string);
+  if (id < 0) {
+     return PREPARE_NEGATIVE_ID;
+  }
+  if (strlen(username) > COLUMN_USERNAME_SIZE) {
+     return PREPARE_STRING_TOO_LONG;
+  }
+  if (strlen(email) > COLUMN_EMAIL_SIZE) {
+     return PREPARE_STRING_TOO_LONG;
+  }
+
+  statement->row_to_insert.id = id;
+  strcpy(statement->row_to_insert.username, username);
+  strcpy(statement->row_to_insert.email, email);
+
   return PREPARE_SUCCESS;
+
+}
+PrepareResult prepare_statement(InputBuffer* input_buffer,
+                                Statement* statement) {
+  if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
+      return prepare_insert(input_buffer, statement);
   }
   if (strcmp(input_buffer->buffer, "select") == 0) {
     statement->type = STATEMENT_SELECT;
@@ -223,6 +247,12 @@ int main(int argc, char* argv[]) {
     switch (prepare_statement(input_buffer, &statement)) {
       case (PREPARE_SUCCESS):
         break;
+      case (PREPARE_NEGATIVE_ID):
+	printf("ID must be positive.\n");
+	continue;
+      case (PREPARE_STRING_TOO_LONG):
+	printf("String is too long.\n");
+	continue;
       case (PREPARE_SYNTAX_ERROR):
 	printf("Syntax error. Could not parse statement.\n");
 	continue;
```
그리고 추가된 테스트들입니다.
```diff
+describe 'database' do
+  def run_script(commands)
+    raw_output = nil
+    IO.popen("./db", "r+") do |pipe|
+      commands.each do |command|
+        pipe.puts command
+      end
+
+      pipe.close_write
+
+      # Read entire output
+      raw_output = pipe.gets(nil)
+    end
+    raw_output.split("\n")
+  end
+
+  it 'inserts and retreives a row' do
+    result = run_script([
+      "insert 1 user1 person1@example.com",
+      "select",
+      ".exit",
+    ])
+    expect(result).to match_array([
+      "db > Executed.",
+      "db > (1, user1, person1@example.com)",
+      "Executed.",
+      "db > ",
+    ])
+  end
+
+  it 'prints error message when table is full' do
+    script = (1..1401).map do |i|
+      "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << ".exit"
+    result = run_script(script)
+    expect(result[-2]).to eq('db > Error: Table full.')
+  end
+
+  it 'allows inserting strings that are the maximum length' do
+    long_username = "a"*32
+    long_email = "a"*255
+    script = [
+      "insert 1 #{long_username} #{long_email}",
+      "select",
+      ".exit",
+    ]
+    result = run_script(script)
+    expect(result).to match_array([
+      "db > Executed.",
+      "db > (1, #{long_username}, #{long_email})",
+      "Executed.",
+      "db > ",
+    ])
+  end
+
+  it 'prints error message if strings are too long' do
+    long_username = "a"*33
+    long_email = "a"*256
+    script = [
+      "insert 1 #{long_username} #{long_email}",
+      "select",
+      ".exit",
+    ]
+    result = run_script(script)
+    expect(result).to match_array([
+      "db > String is too long.",
+      "db > Executed.",
+      "db > ",
+    ])
+  end
+
+  it 'prints an error message if id is negative' do
+    script = [
+      "insert -1 cstack foo@bar.com",
+      "select",
+      ".exit",
+    ]
+    result = run_script(script)
+    expect(result).to match_array([
+      "db > ID must be positive.",
+      "db > Executed.",
+      "db > ",
+    ])
+  end
+end
```
