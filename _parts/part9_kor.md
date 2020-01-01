---
title: 제9 장 - 이진 탐색 및 중복 키
date: 2017-10-01
---

지난 장에서 여전히 키가 정렬되지 않은 순서대로 저장되고 있음을 확인했습니다. 이번 장에서는 그 문제를 해결하며, 추가로 중복된 키를 검사하고 거부하도록 합니다.

현재, `execute_insert()` 함수는 항상 테이블 끝에 삽입을 수행합니다. 끝에 삽입하는 대신에, 삽입할 올바른 위치를 찾고, 해당 위치에 삽입하도록 해야 합니다. 만약 키가 이미 있는 경우 에러를 반환해야 합니다.

```diff
ExecuteResult execute_insert(Statement* statement, Table* table) {
   void* node = get_page(table->pager, table->root_page_num);
-  if ((*leaf_node_num_cells(node) >= LEAF_NODE_MAX_CELLS)) {
+  uint32_t num_cells = (*leaf_node_num_cells(node));
+  if (num_cells >= LEAF_NODE_MAX_CELLS) {
     return EXECUTE_TABLE_FULL;
   }

   Row* row_to_insert = &(statement->row_to_insert);
-  Cursor* cursor = table_end(table);
+  uint32_t key_to_insert = row_to_insert->id;
+  Cursor* cursor = table_find(table, key_to_insert);
+
+  if (cursor->cell_num < num_cells) {
+    uint32_t key_at_index = *leaf_node_key(node, cursor->cell_num);
+    if (key_at_index == key_to_insert) {
+      return EXECUTE_DUPLICATE_KEY;
+    }
+  }

   leaf_node_insert(cursor, row_to_insert->id, row_to_insert);
```

더 이상 `table_end()` 함수는 필요하지 않습니다.

```diff
-Cursor* table_end(Table* table) {
-  Cursor* cursor = malloc(sizeof(Cursor));
-  cursor->table = table;
-  cursor->page_num = table->root_page_num;
-
-  void* root_node = get_page(table->pager, table->root_page_num);
-  uint32_t num_cells = *leaf_node_num_cells(root_node);
-  cursor->cell_num = num_cells;
-  cursor->end_of_table = true;
-
-  return cursor;
-}
```

주어진 키로 트리를 탐색하는 함수로 대체합니다.

```diff
+/*
+주어진 키를 갖는 노드의 위치를 반환합니다.
+키를 갖는 노드가 없는 경우, 
+삽입될 위치를 반환합니다.
+*/
+Cursor* table_find(Table* table, uint32_t key) {
+  uint32_t root_page_num = table->root_page_num;
+  void* root_node = get_page(table->pager, root_page_num);
+
+  if (get_node_type(root_node) == NODE_LEAF) {
+    return leaf_node_find(table, root_page_num, key);
+  } else {
+    printf("Need to implement searching an internal node\n");
+    exit(EXIT_FAILURE);
+  }
+}
```

아직 내부 노드를 구현하지 않았기 때문에 내부 노드를 위한 분기문은 스텁을 사용합니다. 리프 노드에 대해서는 이진 탐색을 수행합니다.

```diff
+Cursor* leaf_node_find(Table* table, uint32_t page_num, uint32_t key) {
+  void* node = get_page(table->pager, page_num);
+  uint32_t num_cells = *leaf_node_num_cells(node);
+
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->page_num = page_num;
+
+  // 이진 탐색
+  uint32_t min_index = 0;
+  uint32_t one_past_max_index = num_cells;
+  while (one_past_max_index != min_index) {
+    uint32_t index = (min_index + one_past_max_index) / 2;
+    uint32_t key_at_index = *leaf_node_key(node, index);
+    if (key == key_at_index) {
+      cursor->cell_num = index;
+      return cursor;
+    }
+    if (key < key_at_index) {
+      one_past_max_index = index;
+    } else {
+      min_index = index + 1;
+    }
+  }
+
+  cursor->cell_num = min_index;
+  return cursor;
+}
```

이 함수는 다음 값들 중 하나를 반환합니다.
- 키의 위치
- 새로운 키 삽입 시 이동이 필요한 또 다른 키의 위치
- 마지막 키 다음 위치

이제 노드의 유형을 확인하기 때문에, 노드에서 유형 값을 가져오고 설정할 수 있는 함수가 필요합니다.

```diff
+NodeType get_node_type(void* node) {
+  uint8_t value = *((uint8_t*)(node + NODE_TYPE_OFFSET));
+  return (NodeType)value;
+}
+
+void set_node_type(void* node, NodeType type) {
+  uint8_t value = type;
+  *((uint8_t*)(node + NODE_TYPE_OFFSET)) = value;
+}
```

단일 바이트로 저장되도록, `uint8_t` 로 먼저 캐스팅해야 합니다.

또한 노드 유형을 초기화 합니다.

```diff
-void initialize_leaf_node(void* node) { *leaf_node_num_cells(node) = 0; }
+void initialize_leaf_node(void* node) {
+  set_node_type(node, NODE_LEAF);
+  *leaf_node_num_cells(node) = 0;
+}
```

마지막으로, 새로운 에러 코드를 만들어 처리합니다.

```diff
-enum ExecuteResult_t { EXECUTE_SUCCESS, EXECUTE_TABLE_FULL };
+enum ExecuteResult_t {
+  EXECUTE_SUCCESS,
+  EXECUTE_DUPLICATE_KEY,
+  EXECUTE_TABLE_FULL
+};
```

```diff
       case (EXECUTE_SUCCESS):
         printf("Executed.\n");
         break;
+      case (EXECUTE_DUPLICATE_KEY):
+        printf("Error: Duplicate key.\n");
+        break;
       case (EXECUTE_TABLE_FULL):
         printf("Error: Table full.\n");
         break;
```

변경 작업으로, 테스트가 정렬된 순서를 확인하도록 변경합니다.

```diff
       "db > Executed.",
       "db > Tree:",
       "leaf (size 3)",
-      "  - 0 : 3",
-      "  - 1 : 1",
-      "  - 2 : 2",
+      "  - 0 : 1",
+      "  - 1 : 2",
+      "  - 2 : 3",
       "db > "
     ])
   end
```

그리고 키 중복 상황에 대한 테스트를 추가합니다.

```diff
+  it 'prints an error message if there is a duplicate id' do
+    script = [
+      "insert 1 user1 person1@example.com",
+      "insert 1 user1 person1@example.com",
+      "select",
+      ".exit",
+    ]
+    result = run_script(script)
+    expect(result).to match_array([
+      "db > Executed.",
+      "db > Error: Duplicate key.",
+      "db > (1, user1, person1@example.com)",
+      "Executed.",
+      "db > ",
+    ])
+  end
```

끝났습니다! 다음 장: 단말 노드 분할 및 새 내부 노드 생성 구현
