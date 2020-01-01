---
title: 제8 장 - B-트리 단말 노드 형식
date: 2017-09-25
---

정렬되지 않은 행 배열에서 B-트리로 테이블의 형식을 변경하고 있습니다. 이것은 여러 장으로 다뤄질 만큼 굉장히 큰 변경 작업입니다. 이번 장을 통해, 단말 노드의 형식을 정의하고 단일 노드 트리에 대한 키/값 쌍 삽입을 구현하게 됩니다. 먼저, 트리 구조로 바꾸는 이유를 상기해보며 시작하겠습니다.

## 다양한 테이블 형식들

현재 형식을 사용하면, 각 페이지가 행들만을 저장하기 때문에 (메타데이터는 저장하지 않음) 공간 효율성이 매우 높습니다. 삽입 연산의 경우 단지 끝에 추가하면 됨으로 매우 빠릅니다. 하지만, 특정 행을 찾기 위해서는 전체 테이블을 탐색해야 합니다. 또한 행을 삭제하는 경우 뒤에 오는 행들을 일일이 옮겨 빈틈을 채우는 작업이 필요합니다.

만약 배열로 저장하지만 id 값으로 행의 정렬을 유지한다면, 특정 id를 이진 탐색으로 찾을 수  있을 것입니다. 그러나, 삽입 시 많은 행을 이동해야 하기 때문에 매우 느릴 것입니다.

이러한 이유로, 트리 구조를 사용합니다. 트리의 각 노드는 행의 개수를 가변적으로 갖게 됩니다. 그래서 각 노드가 몇 개의 행을 갖고 있는지 추적하기 위한 정보를 저장해야 합니다. 추가로 모든 내부 노드들이 어떠한 행도 저장하지 않아 발생하는 공간 낭비가 있습니다. 하지만 큰 데이터베이스 파일을 갖는 대신, 빠른 삽입, 삭제 그리고 탐색 연산을 갖게 됩니다.

|                  | 정렬되지 않은 행 배열  | 정렬된 행 배열       | 노드들의 트리            |
|------------------|------------------------|----------------------|--------------------------|
| 페이지가 갖는 값 | 오직 데이터            | 오직 데이터          | 메타데이터, 주키, 데이터 |
| 페이지 별 행     | 많음                   | 많음                 | 적음                     |
| 삽입             | O(1)                   | O(n)                 | O(log(n))                |
| 삭제             | O(n)                   | O(n)                 | O(log(n))                |
| id를 통한 탐색   | O(n)                   | O(log(n))            | O(log(n))                |

## 노드 헤더 형식

단말 노드와 내부 노드는 다른 형식을 갖습니다. 노드 유형을 관리하기 위해 열거형을 만들겠습니다.

```diff
+typedef enum { NODE_INTERNAL, NODE_LEAF } NodeType;
```

각 노드는 하나의 페이지에 해당합니다. 내부 노드는 자식 노드에 해당하는 페이지 번호를 저장하여 자식 노드를 가리킵니다. B-트리는 페이저에 특정 페이지 번호를 요청하고, 페이지 캐시 내 해당 페이지의 포인터를 얻습니다. 페이지는 페이지 번호 순서대로 데이터베이스 파일에 차례로 저장됩니다.

노드는 페이지 시작 부분에 있는 헤더에 일부 메타데이터를 저장해야 합니다. 모든 노드는 노드 유형, 루트 노드 여부, 그리고 부모 노드에 대한 포인터를 갖습니다. (형제 노드를 찾기 위해서 사용됩니다.) 다음과 같이 헤더 필드의 크기와 오프셋을 상수로 정의합니다.

```diff
+/*
+ * 공통 노드 헤더 형식
+ */
+const uint32_t NODE_TYPE_SIZE = sizeof(uint8_t);
+const uint32_t NODE_TYPE_OFFSET = 0;
+const uint32_t IS_ROOT_SIZE = sizeof(uint8_t);
+const uint32_t IS_ROOT_OFFSET = NODE_TYPE_SIZE;
+const uint32_t PARENT_POINTER_SIZE = sizeof(uint32_t);
+const uint32_t PARENT_POINTER_OFFSET = IS_ROOT_OFFSET + IS_ROOT_SIZE;
+const uint8_t COMMON_NODE_HEADER_SIZE =
+    NODE_TYPE_SIZE + IS_ROOT_SIZE + PARENT_POINTER_SIZE;
```

## 단말 노드 형식

공통 헤더 필드 외에도 단말 노드는 갖고 있는 "셀" 수를 정의해야 합니다. 셀은 키/값 쌍을 말합니다.

```diff
+/*
+ * 단말 노드 헤더 형식
+ */
+const uint32_t LEAF_NODE_NUM_CELLS_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_NUM_CELLS_OFFSET = COMMON_NODE_HEADER_SIZE;
+const uint32_t LEAF_NODE_HEADER_SIZE =
+    COMMON_NODE_HEADER_SIZE + LEAF_NODE_NUM_CELLS_SIZE;
```

단말 노드의 본체는 셀의 배열입니다. 각 셀은 키 뒤에 값 (직렬화된 행)을 갖습니다.

```diff
+/*
+ * 단말 노드 본체 형식
+ */
+const uint32_t LEAF_NODE_KEY_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_KEY_OFFSET = 0;
+const uint32_t LEAF_NODE_VALUE_SIZE = ROW_SIZE;
+const uint32_t LEAF_NODE_VALUE_OFFSET =
+    LEAF_NODE_KEY_OFFSET + LEAF_NODE_KEY_SIZE;
+const uint32_t LEAF_NODE_CELL_SIZE = LEAF_NODE_KEY_SIZE + LEAF_NODE_VALUE_SIZE;
+const uint32_t LEAF_NODE_SPACE_FOR_CELLS = PAGE_SIZE - LEAF_NODE_HEADER_SIZE;
+const uint32_t LEAF_NODE_MAX_CELLS =
+    LEAF_NODE_SPACE_FOR_CELLS / LEAF_NODE_CELL_SIZE;
```

정의한 상수들을 바탕으로, 단말 노드는 다음과 같은 형식을 갖습니다.

{% include image.html url="assets/images/leaf-node-format.png" description="우리의 단말 노드 형식" %}

헤더에서 불 값을 하나의 바이트 공간에 저장하는 것은 비효율적입니다. 하지만 값들을 접근하는 코드를 작성하기 쉽게 만듭니다.

추가로 마지막에 낭비되는 공간이 있습니다. 우리는 헤더 필드 이후부터 가능한 많은 셀을 저장합니다. 하지만 하나의 셀을 저장하기에 불충분한 크기의 공간이 남게 됩니다. 필자는 하나의 셀이 두 노드로 분할되지 않도록 하기 위해 해당 공간을 빈 공간으로 남겨 두었습니다.

## 단말 노드 필드 접근

키, 값 그리고 메타데이터에 접근하는 모든 코드는 정의한 상수를 사용한 포인터 산술 연산입니다.

```diff
+uint32_t* leaf_node_num_cells(void* node) {
+  return node + LEAF_NODE_NUM_CELLS_OFFSET;
+}
+
+void* leaf_node_cell(void* node, uint32_t cell_num) {
+  return node + LEAF_NODE_HEADER_SIZE + cell_num * LEAF_NODE_CELL_SIZE;
+}
+
+uint32_t* leaf_node_key(void* node, uint32_t cell_num) {
+  return leaf_node_cell(node, cell_num);
+}
+
+void* leaf_node_value(void* node, uint32_t cell_num) {
+  return leaf_node_cell(node, cell_num) + LEAF_NODE_KEY_SIZE;
+}
+
+void initialize_leaf_node(void* node) { *leaf_node_num_cells(node) = 0; }
+
```

이러한 함수들은 요청한 값의 포인터를 반환하므로, 게터와 세터로 모두 사용할 수 있습니다.

## 페이저와 테이블 객체 변경

모든 노드는 꽉 차지는 않더라도 정확히 한 페이지씩 차지하게 됩니다. 이것은 페이저가 불완전 페이지에 대한 읽기/쓰기를 고려할 필요가 없음을 의미합니다.
```diff
-void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
+void pager_flush(Pager* pager, uint32_t page_num) {
   if (pager->pages[page_num] == NULL) {
     printf("Tried to flush null page\n");
     exit(EXIT_FAILURE);
@@ -242,7 +337,7 @@ void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
   }
 
   ssize_t bytes_written =
-      write(pager->file_descriptor, pager->pages[page_num], size);
+      write(pager->file_descriptor, pager->pages[page_num], PAGE_SIZE);
 
   if (bytes_written == -1) {
     printf("Error writing: %d\n", errno);
```

```diff
 void db_close(Table* table) {
   Pager* pager = table->pager;
-  uint32_t num_full_pages = table->num_rows / ROWS_PER_PAGE;
 
-  for (uint32_t i = 0; i < num_full_pages; i++) {
+  for (uint32_t i = 0; i < pager->num_pages; i++) {
     if (pager->pages[i] == NULL) {
       continue;
     }
-    pager_flush(pager, i, PAGE_SIZE);
+    pager_flush(pager, i);
     free(pager->pages[i]);
     pager->pages[i] = NULL;
   }
 
-  // 파일의 끝에 불완전한 페이지를 저장할 수도 있습니다.
-  // B-트리로 전환하면 이 작업은 필요하지 않게 됩니다.
-  uint32_t num_additional_rows = table->num_rows % ROWS_PER_PAGE;
-  if (num_additional_rows > 0) {
-    uint32_t page_num = num_full_pages;
-    if (pager->pages[page_num] != NULL) {
-      pager_flush(pager, page_num, num_additional_rows * ROW_SIZE);
-      free(pager->pages[page_num]);
-      pager->pages[page_num] = NULL;
-    }
-  }
-
   int result = close(pager->file_descriptor);
   if (result == -1) {
     printf("Error closing db file.\n");
```

이제 데이터베이스에 행 수를 저장하기 보다 페이지 수를 저장하는 것이 더 합리적입니다. 페이지 수는 특정 테이블이 아닌 데이터베이스에서 사용하기 때문에 테이블 객체가 아닌 페이저 객체에 포함되어야 합니다. B-트리는 루트 노드 페이지 번호를 통해 식별되므로, 테이블 객체가 루트 노드 페이지 정보를 관리해야 합니다.

```diff
 const uint32_t PAGE_SIZE = 4096;
 const uint32_t TABLE_MAX_PAGES = 100;
-const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
-const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
 
 typedef struct {
   int file_descriptor;
   uint32_t file_length;
+  uint32_t num_pages;
   void* pages[TABLE_MAX_PAGES];
 } Pager;
 
 typedef struct {
   Pager* pager;
-  uint32_t num_rows;
+  uint32_t root_page_num;
 } Table;
```

```diff
@@ -127,6 +200,10 @@ void* get_page(Pager* pager, uint32_t page_num) {
     }
 
     pager->pages[page_num] = page;
+
+    if (page_num >= pager->num_pages) {
+      pager->num_pages = page_num + 1;
+    }
   }
 
   return pager->pages[page_num];
```

```diff
@@ -184,6 +269,12 @@ Pager* pager_open(const char* filename) {
   Pager* pager = malloc(sizeof(Pager));
   pager->file_descriptor = fd;
   pager->file_length = file_length;
+  pager->num_pages = (file_length / PAGE_SIZE);
+
+  if (file_length % PAGE_SIZE != 0) {
+    printf("Db file is not a whole number of pages. Corrupt file.\n");
+    exit(EXIT_FAILURE);
+  }
 
   for (uint32_t i = 0; i < TABLE_MAX_PAGES; i++) {
     pager->pages[i] = NULL;
```

## 커서 객체 변경

커서는 테이블에서 위치를 나타냅니다. 테이블이 단순 행 배열이었을 때, 행 번호를 통해 쉽게 접근이 가능했습니다. 이제는 트리로 변경되었고, 노드의 페이지 번호와 해당 노드 내 셀 번호로 위치를 식별합니다.

```diff
 typedef struct {
   Table* table;
-  uint32_t row_num;
+  uint32_t page_num;
+  uint32_t cell_num;
   bool end_of_table;  // 마지막 행의 다음 위치를 가리키고 있음을 나타냅니다.
 } Cursor;
```

```diff
 Cursor* table_start(Table* table) {
   Cursor* cursor = malloc(sizeof(Cursor));
   cursor->table = table;
-  cursor->row_num = 0;
-  cursor->end_of_table = (table->num_rows == 0);
+  cursor->page_num = table->root_page_num;
+  cursor->cell_num = 0;
+
+  void* root_node = get_page(table->pager, table->root_page_num);
+  uint32_t num_cells = *leaf_node_num_cells(root_node);
+  cursor->end_of_table = (num_cells == 0);
 
   return cursor;
 }
```

```diff
 Cursor* table_end(Table* table) {
   Cursor* cursor = malloc(sizeof(Cursor));
   cursor->table = table;
-  cursor->row_num = table->num_rows;
+  cursor->page_num = table->root_page_num;
+
+  void* root_node = get_page(table->pager, table->root_page_num);
+  uint32_t num_cells = *leaf_node_num_cells(root_node);
+  cursor->cell_num = num_cells;
   cursor->end_of_table = true;
 
   return cursor;
 }
```

```diff
 void* cursor_value(Cursor* cursor) {
-  uint32_t row_num = cursor->row_num;
-  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  uint32_t page_num = cursor->page_num;
   void* page = get_page(cursor->table->pager, page_num);
-  uint32_t row_offset = row_num % ROWS_PER_PAGE;
-  uint32_t byte_offset = row_offset * ROW_SIZE;
-  return page + byte_offset;
+  return leaf_node_value(page, cursor->cell_num);
 }
```

```diff
 void cursor_advance(Cursor* cursor) {
-  cursor->row_num += 1;
-  if (cursor->row_num >= cursor->table->num_rows) {
+  uint32_t page_num = cursor->page_num;
+  void* node = get_page(cursor->table->pager, page_num);
+
+  cursor->cell_num += 1;
+  if (cursor->cell_num >= (*leaf_node_num_cells(node))) {
     cursor->end_of_table = true;
   }
 }
```

## 단말 노드 삽입

이번 장에서는 단일 노드 트리에 대한 구현을 진행합니다. 먼저 트리가 빈 단말 노드로 시작함을 다시 떠올려 보기 바랍니다.

{% include image.html url="assets/images/btree1.png" description="빈 B-트리" %}

키/값 쌍은 단말 노드가 가득 찰 때까지 추가될 수 있습니다.

{% include image.html url="assets/images/btree2.png" description="단일 노드 B-트리" %}

데이터베이스를 처음 열면 파일이 비어있으므로, 0번 페이지를 빈 단말 노드 (루트 노드)로 초기화합니다.

```diff
 Table* db_open(const char* filename) {
   Pager* pager = pager_open(filename);
-  uint32_t num_rows = pager->file_length / ROW_SIZE;
 
   Table* table = malloc(sizeof(Table));
   table->pager = pager;
-  table->num_rows = num_rows;
+  table->root_page_num = 0;
+
+  if (pager->num_pages == 0) {
+    // 새 데이터베이스 파일. 페이지 0을 단말 노드로 초기화합니다.
+    void* root_node = get_page(pager, 0);
+    initialize_leaf_node(root_node);
+  }
 
   return table;
 }
```

다음으로 키/값 쌍을 단말 노드에 삽입하는 함수를 생성합니다. 쌍이 삽입될 위치를 나타내는 커서를 입력으로 받습니다.

```diff
+void leaf_node_insert(Cursor* cursor, uint32_t key, Row* value) {
+  void* node = get_page(cursor->table->pager, cursor->page_num);
+
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  if (num_cells >= LEAF_NODE_MAX_CELLS) {
+    // 노드가 가득 찬 경우
+    printf("Need to implement splitting a leaf node.\n");
+    exit(EXIT_FAILURE);
+  }
+
+  if (cursor->cell_num < num_cells) {
+    // 새로운 셀을 위한 공간 생성
+    for (uint32_t i = num_cells; i > cursor->cell_num; i--) {
+      memcpy(leaf_node_cell(node, i), leaf_node_cell(node, i - 1),
+             LEAF_NODE_CELL_SIZE);
+    }
+  }
+
+  *(leaf_node_num_cells(node)) += 1;
+  *(leaf_node_key(node, cursor->cell_num)) = key;
+  serialize_row(value, leaf_node_value(node, cursor->cell_num));
+}
+
```

아직 분할이 구현되지 않았으므로 노드가 가득 차면 에러를 발생합니다. 다음으로 새로운 셀의 공간을 만들기 위해 기존 셀들을 오른쪽으로 한 칸씩 이동시킵니다. 그런 다음 빈 공간에 새 키/값을 씁니다.

단일 노드 트리로 가정했기 때문에 `execute_insert()` 함수는 이 헬퍼 함수를 호출하기만 하면 됩니다.

```diff
 ExecuteResult execute_insert(Statement* statement, Table* table) {
-  if (table->num_rows >= TABLE_MAX_ROWS) {
+  void* node = get_page(table->pager, table->root_page_num);
+  if ((*leaf_node_num_cells(node) >= LEAF_NODE_MAX_CELLS)) {
     return EXECUTE_TABLE_FULL;
   }
 
   Row* row_to_insert = &(statement->row_to_insert);
   Cursor* cursor = table_end(table);
 
-  serialize_row(row_to_insert, cursor_value(cursor));
-  table->num_rows += 1;
+  leaf_node_insert(cursor, row_to_insert->id, row_to_insert);
 
   free(cursor);
```

변경을 통해, 데이터베이스는 전과 같이 작동합니다! 루트 노드를 아직 분할할 수 없기 때문에 중간에 "Table Full" 에러를 반환하는 것을 제외하면 말이죠.

그렇다면, 단말 노드는 몇 개의 행을 저장할 수 있을까요?

## 상수 출력 명령

몇 가지 주요한 상숫값을 출력하기 위해 메타 명령을 추가합니다.

```diff
+void print_constants() {
+  printf("ROW_SIZE: %d\n", ROW_SIZE);
+  printf("COMMON_NODE_HEADER_SIZE: %d\n", COMMON_NODE_HEADER_SIZE);
+  printf("LEAF_NODE_HEADER_SIZE: %d\n", LEAF_NODE_HEADER_SIZE);
+  printf("LEAF_NODE_CELL_SIZE: %d\n", LEAF_NODE_CELL_SIZE);
+  printf("LEAF_NODE_SPACE_FOR_CELLS: %d\n", LEAF_NODE_SPACE_FOR_CELLS);
+  printf("LEAF_NODE_MAX_CELLS: %d\n", LEAF_NODE_MAX_CELLS);
+}
+
@@ -294,6 +376,14 @@ MetaCommandResult do_meta_command(InputBuffer* input_buffer, Table* table) {
   if (strcmp(input_buffer->buffer, ".exit") == 0) {
     db_close(table);
     exit(EXIT_SUCCESS);
+  } else if (strcmp(input_buffer->buffer, ".constants") == 0) {
+    printf("Constants:\n");
+    print_constants();
+    return META_COMMAND_SUCCESS;
   } else {
     return META_COMMAND_UNRECOGNIZED_COMMAND;
   }
```

또한 테스트를 추가하여 상숫값이 다른 경우 경고가 발생토록 합니다.
```diff
+  it 'prints constants' do
+    script = [
+      ".constants",
+      ".exit",
+    ]
+    result = run_script(script)
+
+    expect(result).to match_array([
+      "db > Constants:",
+      "ROW_SIZE: 293",
+      "COMMON_NODE_HEADER_SIZE: 6",
+      "LEAF_NODE_HEADER_SIZE: 10",
+      "LEAF_NODE_CELL_SIZE: 297",
+      "LEAF_NODE_SPACE_FOR_CELLS: 4086",
+      "LEAF_NODE_MAX_CELLS: 13",
+      "db > ",
+    ])
+  end
```

우리 테이블은 지금 13 행을 수용할 수 있습니다!

## 트리 시각화

또한, 디버깅과 시각화를 돕기 위해 B-트리 형태를 출력하는 메타 명령을 추가합니다.

```diff
+void print_leaf_node(void* node) {
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  printf("leaf (size %d)\n", num_cells);
+  for (uint32_t i = 0; i < num_cells; i++) {
+    uint32_t key = *leaf_node_key(node, i);
+    printf("  - %d : %d\n", i, key);
+  }
+}
+
```

```diff
@@ -294,6 +376,14 @@ MetaCommandResult do_meta_command(InputBuffer* input_buffer, Table* table) {
   if (strcmp(input_buffer->buffer, ".exit") == 0) {
     db_close(table);
     exit(EXIT_SUCCESS);
+  } else if (strcmp(input_buffer->buffer, ".btree") == 0) {
+    printf("Tree:\n");
+    print_leaf_node(get_page(table->pager, 0));
+    return META_COMMAND_SUCCESS;
   } else if (strcmp(input_buffer->buffer, ".constants") == 0) {
     printf("Constants:\n");
     print_constants();
     return META_COMMAND_SUCCESS;
   } else {
     return META_COMMAND_UNRECOGNIZED_COMMAND;
   }
```

그리고 테스트도 추가합니다.

```diff
+  it 'allows printing out the structure of a one-node btree' do
+    script = [3, 1, 2].map do |i|
+      "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << ".btree"
+    script << ".exit"
+    result = run_script(script)
+
+    expect(result).to match_array([
+      "db > Executed.",
+      "db > Executed.",
+      "db > Executed.",
+      "db > Tree:",
+      "leaf (size 3)",
+      "  - 0 : 3",
+      "  - 1 : 1",
+      "  - 2 : 2",
+      "db > "
+    ])
+  end
```

아직 행을 정렬된 순서로 저장하진 않습니다. `execute_insert()` 함수 가 `table_end()` 함수가 반환한 위치에 단말 노드를 삽입하고 있음을 주목하기 바랍니다. 따라서, 이전과 마찬가지로 삽입된 순서대로 저장됩니다.

## 다음 장에서

퇴보한 것처럼 보일 수 있습니다. 이전 보다 적은 행을 저장하고, 여전히 행은 정렬되지 않습니다. 하지만 처음에 말했듯이, 굉장히 큰 변경 작업으로써 다루기 쉬운 단계들로 나눠 접근 하는 것이 중요합니다.

다음 장에서는, 기본 키를 통한 레코드 탐색을 구현하며 정렬된 순서대로 행을 저장할 것입니다.

## 변경된 부분

```diff
@@ -62,29 +62,101 @@ const uint32_t ROW_SIZE = ID_SIZE + USERNAME_SIZE + EMAIL_SIZE;

 const uint32_t PAGE_SIZE = 4096;
 #define TABLE_MAX_PAGES 100
-const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
-const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
 
 typedef struct {
   int file_descriptor;
   uint32_t file_length;
+  uint32_t num_pages;
   void* pages[TABLE_MAX_PAGES];
 } Pager;
 
 typedef struct {
   Pager* pager;
-  uint32_t num_rows;
+  uint32_t root_page_num;
 } Table;
 
 typedef struct {
   Table* table;
-  uint32_t row_num;
+  uint32_t page_num;
+  uint32_t cell_num;
   bool end_of_table;  // 마지막 행의 다음 위치를 가리키고 있음을 나타냅니다.
 } Cursor;

+typedef enum { NODE_INTERNAL, NODE_LEAF } NodeType;
+
+/*
+ * 공통 노드 헤더 형식
+ */
+const uint32_t NODE_TYPE_SIZE = sizeof(uint8_t);
+const uint32_t NODE_TYPE_OFFSET = 0;
+const uint32_t IS_ROOT_SIZE = sizeof(uint8_t);
+const uint32_t IS_ROOT_OFFSET = NODE_TYPE_SIZE;
+const uint32_t PARENT_POINTER_SIZE = sizeof(uint32_t);
+const uint32_t PARENT_POINTER_OFFSET = IS_ROOT_OFFSET + IS_ROOT_SIZE;
+const uint8_t COMMON_NODE_HEADER_SIZE =
+    NODE_TYPE_SIZE + IS_ROOT_SIZE + PARENT_POINTER_SIZE;
+
+/*
+ * 단말 노드 헤더 형식
+ */
+const uint32_t LEAF_NODE_NUM_CELLS_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_NUM_CELLS_OFFSET = COMMON_NODE_HEADER_SIZE;
+const uint32_t LEAF_NODE_HEADER_SIZE =
+    COMMON_NODE_HEADER_SIZE + LEAF_NODE_NUM_CELLS_SIZE;
+
+/*
+ * 단말 노드 본체 형식
+ */
+const uint32_t LEAF_NODE_KEY_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_KEY_OFFSET = 0;
+const uint32_t LEAF_NODE_VALUE_SIZE = ROW_SIZE;
+const uint32_t LEAF_NODE_VALUE_OFFSET =
+    LEAF_NODE_KEY_OFFSET + LEAF_NODE_KEY_SIZE;
+const uint32_t LEAF_NODE_CELL_SIZE = LEAF_NODE_KEY_SIZE + LEAF_NODE_VALUE_SIZE;
+const uint32_t LEAF_NODE_SPACE_FOR_CELLS = PAGE_SIZE - LEAF_NODE_HEADER_SIZE;
+const uint32_t LEAF_NODE_MAX_CELLS =
+    LEAF_NODE_SPACE_FOR_CELLS / LEAF_NODE_CELL_SIZE;
+
+uint32_t* leaf_node_num_cells(void* node) {
+  return node + LEAF_NODE_NUM_CELLS_OFFSET;
+}
+
+void* leaf_node_cell(void* node, uint32_t cell_num) {
+  return node + LEAF_NODE_HEADER_SIZE + cell_num * LEAF_NODE_CELL_SIZE;
+}
+
+uint32_t* leaf_node_key(void* node, uint32_t cell_num) {
+  return leaf_node_cell(node, cell_num);
+}
+
+void* leaf_node_value(void* node, uint32_t cell_num) {
+  return leaf_node_cell(node, cell_num) + LEAF_NODE_KEY_SIZE;
+}
+
+void print_constants() {
+  printf("ROW_SIZE: %d\n", ROW_SIZE);
+  printf("COMMON_NODE_HEADER_SIZE: %d\n", COMMON_NODE_HEADER_SIZE);
+  printf("LEAF_NODE_HEADER_SIZE: %d\n", LEAF_NODE_HEADER_SIZE);
+  printf("LEAF_NODE_CELL_SIZE: %d\n", LEAF_NODE_CELL_SIZE);
+  printf("LEAF_NODE_SPACE_FOR_CELLS: %d\n", LEAF_NODE_SPACE_FOR_CELLS);
+  printf("LEAF_NODE_MAX_CELLS: %d\n", LEAF_NODE_MAX_CELLS);
+}
+
+void print_leaf_node(void* node) {
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  printf("leaf (size %d)\n", num_cells);
+  for (uint32_t i = 0; i < num_cells; i++) {
+    uint32_t key = *leaf_node_key(node, i);
+    printf("  - %d : %d\n", i, key);
+  }
+}
+
 void print_row(Row* row) {
     printf("(%d, %s, %s)\n", row->id, row->username, row->email);
 }
@@ -101,6 +173,8 @@ void deserialize_row(void *source, Row* destination) {
     memcpy(&(destination->email), source + EMAIL_OFFSET, EMAIL_SIZE);
 }
 
+void initialize_leaf_node(void* node) { *leaf_node_num_cells(node) = 0; }
+
 void* get_page(Pager* pager, uint32_t page_num) {
   if (page_num > TABLE_MAX_PAGES) {
     printf("Tried to fetch page number out of bounds. %d > %d\n", page_num,
@@ -128,6 +202,10 @@ void* get_page(Pager* pager, uint32_t page_num) {
     }
 
     pager->pages[page_num] = page;
+
+    if (page_num >= pager->num_pages) {
+      pager->num_pages = page_num + 1;
+    }
   }
 
   return pager->pages[page_num];
@@ -136,8 +214,12 @@ void* get_page(Pager* pager, uint32_t page_num) {
 Cursor* table_start(Table* table) {
   Cursor* cursor = malloc(sizeof(Cursor));
   cursor->table = table;
-  cursor->row_num = 0;
-  cursor->end_of_table = (table->num_rows == 0);
+  cursor->page_num = table->root_page_num;
+  cursor->cell_num = 0;
+
+  void* root_node = get_page(table->pager, table->root_page_num);
+  uint32_t num_cells = *leaf_node_num_cells(root_node);
+  cursor->end_of_table = (num_cells == 0);
 
   return cursor;
 }
@@ -145,24 +227,28 @@ Cursor* table_start(Table* table) {
 Cursor* table_end(Table* table) {
   Cursor* cursor = malloc(sizeof(Cursor));
   cursor->table = table;
-  cursor->row_num = table->num_rows;
+  cursor->page_num = table->root_page_num;
+
+  void* root_node = get_page(table->pager, table->root_page_num);
+  uint32_t num_cells = *leaf_node_num_cells(root_node);
+  cursor->cell_num = num_cells;
   cursor->end_of_table = true;
 
   return cursor;
 }
 
 void* cursor_value(Cursor* cursor) {
-  uint32_t row_num = cursor->row_num;
-  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  uint32_t page_num = cursor->page_num;
   void* page = get_page(cursor->table->pager, page_num);
-  uint32_t row_offset = row_num % ROWS_PER_PAGE;
-  uint32_t byte_offset = row_offset * ROW_SIZE;
-  return page + byte_offset;
+  return leaf_node_value(page, cursor->cell_num);
 }
 
 void cursor_advance(Cursor* cursor) {
-  cursor->row_num += 1;
-  if (cursor->row_num >= cursor->table->num_rows) {
+  uint32_t page_num = cursor->page_num;
+  void* node = get_page(cursor->table->pager, page_num);
+
+  cursor->cell_num += 1;
+  if (cursor->cell_num >= (*leaf_node_num_cells(node))) {
     cursor->end_of_table = true;
   }
 }
@@ -185,6 +271,12 @@ Pager* pager_open(const char* filename) {
   Pager* pager = malloc(sizeof(Pager));
   pager->file_descriptor = fd;
   pager->file_length = file_length;
+  pager->num_pages = (file_length / PAGE_SIZE);
+
+  if (file_length % PAGE_SIZE != 0) {
+    printf("Db file is not a whole number of pages. Corrupt file.\n");
+    exit(EXIT_FAILURE);
+  }
 
   for (uint32_t i = 0; i < TABLE_MAX_PAGES; i++) {
     pager->pages[i] = NULL;
@@ -194,11 +285,15 @@ Pager* pager_open(const char* filename) {
@@ -195,11 +287,16 @@ Pager* pager_open(const char* filename) {
 
 Table* db_open(const char* filename) {
   Pager* pager = pager_open(filename);
-  uint32_t num_rows = pager->file_length / ROW_SIZE;
 
   Table* table = malloc(sizeof(Table));
   table->pager = pager;
-  table->num_rows = num_rows;
+  table->root_page_num = 0;
+
+  if (pager->num_pages == 0) {
+    // 새 데이터베이스 파일. 페이지 0을 단말 노드로 초기화합니다.
+    void* root_node = get_page(pager, 0);
+    initialize_leaf_node(root_node);
+  }
 
   return table;
 }
@@ -234,7 +331,7 @@ void close_input_buffer(InputBuffer* input_buffer) {
     free(input_buffer);
 }
 
-void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
+void pager_flush(Pager* pager, uint32_t page_num) {
   if (pager->pages[page_num] == NULL) {
     printf("Tried to flush null page\n");
     exit(EXIT_FAILURE);
@@ -242,7 +337,7 @@ void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
@@ -249,7 +346,7 @@ void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
   }
 
   ssize_t bytes_written =
-      write(pager->file_descriptor, pager->pages[page_num], size);
+      write(pager->file_descriptor, pager->pages[page_num], PAGE_SIZE);
 
   if (bytes_written == -1) {
     printf("Error writing: %d\n", errno);
@@ -252,29 +347,16 @@ void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
@@ -260,29 +357,16 @@ void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
 
 void db_close(Table* table) {
   Pager* pager = table->pager;
-  uint32_t num_full_pages = table->num_rows / ROWS_PER_PAGE;
 
-  for (uint32_t i = 0; i < num_full_pages; i++) {
+  for (uint32_t i = 0; i < pager->num_pages; i++) {
     if (pager->pages[i] == NULL) {
       continue;
     }
-    pager_flush(pager, i, PAGE_SIZE);
+    pager_flush(pager, i);
     free(pager->pages[i]);
     pager->pages[i] = NULL;
   }
 
-  // 파일의 끝에 불완전한 페이지를 저장할 수도 있습니다.
-  // B-트리로 전환하면 이 작업은 필요하지 않게 됩니다.
-  uint32_t num_additional_rows = table->num_rows % ROWS_PER_PAGE;
-  if (num_additional_rows > 0) {
-    uint32_t page_num = num_full_pages;
-    if (pager->pages[page_num] != NULL) {
-      pager_flush(pager, page_num, num_additional_rows * ROW_SIZE);
-      free(pager->pages[page_num]);
-      pager->pages[page_num] = NULL;
-    }
-  }
-
   int result = close(pager->file_descriptor);
   if (result == -1) {
     printf("Error closing db file.\n");
@@ -305,6 +389,14 @@ MetaCommandResult do_meta_command(InputBuffer* input_buffer, Table *table) {
   if (strcmp(input_buffer->buffer, ".exit") == 0) {
     db_close(table);
     exit(EXIT_SUCCESS);
+  } else if (strcmp(input_buffer->buffer, ".btree") == 0) {
+    printf("Tree:\n");
+    print_leaf_node(get_page(table->pager, 0));
+    return META_COMMAND_SUCCESS;
+  } else if (strcmp(input_buffer->buffer, ".constants") == 0) {
+    printf("Constants:\n");
+    print_constants();
+    return META_COMMAND_SUCCESS;
   } else {
     return META_COMMAND_UNRECOGNIZED_COMMAND;
   }
@@ -354,16 +446,39 @@ PrepareResult prepare_statement(InputBuffer* input_buffer,
   return PREPARE_UNRECOGNIZED_STATEMENT;
 }
 
+void leaf_node_insert(Cursor* cursor, uint32_t key, Row* value) {
+  void* node = get_page(cursor->table->pager, cursor->page_num);
+
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  if (num_cells >= LEAF_NODE_MAX_CELLS) {
+    // 노드가 가득 찬 경우
+    printf("Need to implement splitting a leaf node.\n");
+    exit(EXIT_FAILURE);
+  }
+
+  if (cursor->cell_num < num_cells) {
+    // 새로운 셀을 위한 공간 생성
+    for (uint32_t i = num_cells; i > cursor->cell_num; i--) {
+      memcpy(leaf_node_cell(node, i), leaf_node_cell(node, i - 1),
+             LEAF_NODE_CELL_SIZE);
+    }
+  }
+
+  *(leaf_node_num_cells(node)) += 1;
+  *(leaf_node_key(node, cursor->cell_num)) = key;
+  serialize_row(value, leaf_node_value(node, cursor->cell_num));
+}
+
 ExecuteResult execute_insert(Statement* statement, Table* table) {
-  if (table->num_rows >= TABLE_MAX_ROWS) {
+  void* node = get_page(table->pager, table->root_page_num);
+  if ((*leaf_node_num_cells(node) >= LEAF_NODE_MAX_CELLS)) {
     return EXECUTE_TABLE_FULL;
   }
 
   Row* row_to_insert = &(statement->row_to_insert);
   Cursor* cursor = table_end(table);
 
-  serialize_row(row_to_insert, cursor_value(cursor));
-  table->num_rows += 1;
+  leaf_node_insert(cursor, row_to_insert->id, row_to_insert);
 
   free(cursor);
```

And the specs:
```diff
+  it 'allows printing out the structure of a one-node btree' do
+    script = [3, 1, 2].map do |i|
+      "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << ".btree"
+    script << ".exit"
+    result = run_script(script)
+
+    expect(result).to match_array([
+      "db > Executed.",
+      "db > Executed.",
+      "db > Executed.",
+      "db > Tree:",
+      "leaf (size 3)",
+      "  - 0 : 3",
+      "  - 1 : 1",
+      "  - 2 : 2",
+      "db > "
+    ])
+  end
+
+  it 'prints constants' do
+    script = [
+      ".constants",
+      ".exit",
+    ]
+    result = run_script(script)
+
+    expect(result).to match_array([
+      "db > Constants:",
+      "ROW_SIZE: 293",
+      "COMMON_NODE_HEADER_SIZE: 6",
+      "LEAF_NODE_HEADER_SIZE: 10",
+      "LEAF_NODE_CELL_SIZE: 297",
+      "LEAF_NODE_SPACE_FOR_CELLS: 4086",
+      "LEAF_NODE_MAX_CELLS: 13",
+      "db > ",
+    ])
+  end
 end
```
