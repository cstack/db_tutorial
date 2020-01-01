---
title: 제6 장 - 커서 추상화
date: 2017-09-10
---

이번 장은 지난 장 보다 분량이 적습니다. B-트리 구현을 쉽게 하기 위해 작은 개선 작업을 진행합니다.

이번 장에서는 테이블의 위치를 표현하는 `Cursor` 객체를 추가하게 됩니다. 커서를 통해 수행하고자 하는 작업은 다음과 같습니다. 

- 테이블의 시작을 가리키는 커서 생성
- 테이블의 끝을 가리키는 커서 생성
- 커서가 가리키는 행 접근
- 커서를 다음 행으로 이동

이러한 동작들을 지금부터 구현해 보겠습니다. 차후에는 다음과 같은 동작도 필요할 것입니다.

- 커서가 가리키는 행 삭제
- 커서가 가리키는 행 수정
- 주어진 ID를 통해 테이블을 검색하고 해당 행을 가리키는 커서 생성

거두 절미하고 바로 시작하겠습니다. `Cursor` 데이터 타입은 다음과 같습니다.

```diff
+typedef struct {
+  Table* table;
+  uint32_t row_num;
+  bool end_of_table;  // 마지막 행의 다음 위치를 가리키고 있음을 나타냅니다.
+} Cursor;
```

현재 테이블 데이터 구조를 고려하여, 테이블에서 위치를 식별하는 데 필요한 행번호를 멤버 변수로 갖습니다.

또한 테이블에 대한 참조를 멤버 변수로 갖습니다. (따라서 커서 관련 함수들이 단지 커서만을 매개변수로 받을 수 있게 됩니다.)

마지막으로, 불 형식의 `end_of_table` 을 갖습니다. 커서가 마지막 행의 다음 위치를 가리키고 있음을 나타냅니다. (표의 마지막 행의 다음 위치는 행이 삽입될 곳입니다.)

`table_start()` 와 `table_end()` 는 새로운 커서를 생성합니다.

```diff
+Cursor* table_start(Table* table) {
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->row_num = 0;
+  cursor->end_of_table = (table->num_rows == 0);
+
+  return cursor;
+}
+
+Cursor* table_end(Table* table) {
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->row_num = table->num_rows;
+  cursor->end_of_table = true;
+
+  return cursor;
+}
```

`row_slot()` 함수는 `cursor_value()` 로 변경되며, 이 함수는 커서가 갖고 있는 정보를 통해 행에 위치를 포인터로 반환합니다.

```diff
-void* row_slot(Table* table, uint32_t row_num) {
+void* cursor_value(Cursor* cursor) {
+  uint32_t row_num = cursor->row_num;
   uint32_t page_num = row_num / ROWS_PER_PAGE;
-  void* page = get_page(table->pager, page_num);
+  void* page = get_page(cursor->table->pager, page_num);
   uint32_t row_offset = row_num % ROWS_PER_PAGE;
   uint32_t byte_offset = row_offset * ROW_SIZE;
   return page + byte_offset;
 }
```

현재 우리의 테이블 구조에서는 간단히 행 번호를 증가시켜 커서를 이동할 수 있습니다. B-트리에서 이 작업은 좀 더 복잡해질 것입니다.

```diff
+void cursor_advance(Cursor* cursor) {
+  cursor->row_num += 1;
+  if (cursor->row_num >= cursor->table->num_rows) {
+    cursor->end_of_table = true;
+  }
+}
```

마지막으로 "가상 머신" 함수들이 커서를 사용하도록 변경합니다. 행 삽입 시에는, 테이블 끝을 가리키는 커서를 생성하고 해당 위치에 행을 삽입한 후, 커서를 닫습니다.

```diff
   Row* row_to_insert = &(statement->row_to_insert);
+  Cursor* cursor = table_end(table);

-  serialize_row(row_to_insert, row_slot(table, table->num_rows));
+  serialize_row(row_to_insert, cursor_value(cursor));
   table->num_rows += 1;

+  free(cursor);
+
   return EXECUTE_SUCCESS;
 }
 ```

테이블의 모든 행을 대상으로 SELECT 작업을 수행하는 경우, 테이블 시작 커서를 생성하고, 행을 출력한 후 커서를 다음 행으로 이동시킵니다. 이 작업을 테이블 끝에 도달할 때까지 반복 수행합니다.

```diff
 ExecuteResult execute_select(Statement* statement, Table* table) {
+  Cursor* cursor = table_start(table);
+
   Row row;
-  for (uint32_t i = 0; i < table->num_rows; i++) {
-    deserialize_row(row_slot(table, i), &row);
+  while (!(cursor->end_of_table)) {
+    deserialize_row(cursor_value(cursor), &row);
     print_row(&row);
+    cursor_advance(cursor);
   }
+
+  free(cursor);
+
   return EXECUTE_SUCCESS;
 }
 ```

좋습니다. 시작에서 말했듯이, 굉장히 짧은 개선 작업입니다. 이 작업은 테이블 구조를 B-트리로 변경할 때 큰 도움이 될 것입니다. 개선 작업을 통해, `execute_select()` 와 `execute_insert()` 는 테이블 저장 방식을 알지 못해도 커서를 통해 테이블과 상호작용할 수 있게 되었습니다.

지금까지 변경된 부분은 다음과 같습니다.
```diff
@@ -78,6 +78,13 @@ struct {
 } Table;

+typedef struct {
+  Table* table;
+  uint32_t row_num;
+  bool end_of_table; // 마지막 행의 다음 위치를 가리키고 있음을 나타냅니다.
+} Cursor;
+
 void print_row(Row* row) {
     printf("(%d, %s, %s)\n", row->id, row->username, row->email);
 }
@@ -126,12 +133,38 @@ void* get_page(Pager* pager, uint32_t page_num) {
     return pager->pages[page_num];
 }

-void* row_slot(Table* table, uint32_t row_num) {
-  uint32_t page_num = row_num / ROWS_PER_PAGE;
-  void *page = get_page(table->pager, page_num);
-  uint32_t row_offset = row_num % ROWS_PER_PAGE;
-  uint32_t byte_offset = row_offset * ROW_SIZE;
-  return page + byte_offset;
+Cursor* table_start(Table* table) {
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->row_num = 0;
+  cursor->end_of_table = (table->num_rows == 0);
+
+  return cursor;
+}
+
+Cursor* table_end(Table* table) {
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->row_num = table->num_rows;
+  cursor->end_of_table = true;
+
+  return cursor;
+}
+
+void* cursor_value(Cursor* cursor) {
+  uint32_t row_num = cursor->row_num;
+  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  void *page = get_page(cursor->table->pager, page_num);
+  uint32_t row_offset = row_num % ROWS_PER_PAGE;
+  uint32_t byte_offset = row_offset * ROW_SIZE;
+  return page + byte_offset;
+}
+
+void cursor_advance(Cursor* cursor) {
+  cursor->row_num += 1;
+  if (cursor->row_num >= cursor->table->num_rows) {
+    cursor->end_of_table = true;
+  }
 }

 Pager* pager_open(const char* filename) {
@@ -327,19 +360,28 @@ ExecuteResult execute_insert(Statement* statement, Table* table) {
     }

   Row* row_to_insert = &(statement->row_to_insert);
+  Cursor* cursor = table_end(table);

-  serialize_row(row_to_insert, row_slot(table, table->num_rows));
+  serialize_row(row_to_insert, cursor_value(cursor));
   table->num_rows += 1;

+  free(cursor);
+
   return EXECUTE_SUCCESS;
 }

 ExecuteResult execute_select(Statement* statement, Table* table) {
+  Cursor* cursor = table_start(table);
+
   Row row;
-  for (uint32_t i = 0; i < table->num_rows; i++) {
-     deserialize_row(row_slot(table, i), &row);
+  while (!(cursor->end_of_table)) {
+     deserialize_row(cursor_value(cursor), &row);
      print_row(&row);
+     cursor_advance(cursor);
   }
+
+  free(cursor);
+
   return EXECUTE_SUCCESS;
 }
```
