---
title: 제12 장 - 다중 레벨 B-Tree 순회
date: 2017-11-11
---

이제 다중 레벨 B-트리를 만들 수 있게 되었습니다. 하지만 그 과정에서 우리의 `select` 문이 망가졌습니다. 다음은 15개 행을 삽입한 후 출력을 시도하는 테스트 케이스입니다.

```diff
+  it 'prints all rows in a multi-level tree' do
+    script = []
+    (1..15).each do |i|
+      script << "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << "select"
+    script << ".exit"
+    result = run_script(script)
+
+    expect(result[15...result.length]).to match_array([
+      "db > (1, user1, person1@example.com)",
+      "(2, user2, person2@example.com)",
+      "(3, user3, person3@example.com)",
+      "(4, user4, person4@example.com)",
+      "(5, user5, person5@example.com)",
+      "(6, user6, person6@example.com)",
+      "(7, user7, person7@example.com)",
+      "(8, user8, person8@example.com)",
+      "(9, user9, person9@example.com)",
+      "(10, user10, person10@example.com)",
+      "(11, user11, person11@example.com)",
+      "(12, user12, person12@example.com)",
+      "(13, user13, person13@example.com)",
+      "(14, user14, person14@example.com)",
+      "(15, user15, person15@example.com)",
+      "Executed.", "db > ",
+    ])
+  end
```

하지만 테스트 케이스를 실행했을 때 실제로 출력되는 것은 다음과 같습니다.

```
db > select
(2, user1, person1@example.com)
Executed.
```

결과가 이상합니다. 한 행만 출력하며, 그 행조차 손상(ID와 사용자 ID의 불일치) 되었습니다.

이상한 결과는 `execute_select()` 가 테이블의 처음에서 시작되고, 또 현재 `table_start()` 가 루트 노드의 0번 셀을 반환하도록 구현되어 발생합니다. 하지만 루트 노드는 아무행도 갖지 않는 내부 노드입니다. 따라서 루트 노드가 단말 노드였을 때 남겨진 것이 출력되는 것으로 보입니다. `execute_select()` 는 가장 왼쪽 단말 노드의 0번 셀을 제대로 반환해야 합니다.

따라서 기존 구현은 제거합니다.

```diff
-Cursor* table_start(Table* table) {
-  Cursor* cursor = malloc(sizeof(Cursor));
-  cursor->table = table;
-  cursor->page_num = table->root_page_num;
-  cursor->cell_num = 0;
-
-  void* root_node = get_page(table->pager, table->root_page_num);
-  uint32_t num_cells = *leaf_node_num_cells(root_node);
-  cursor->end_of_table = (num_cells == 0);
-
-  return cursor;
-}
```

그리고 키 0(최소 키)을 찾는 새로운 구현을 추가합니다. 키 0이 테이블에 없어도, 이 함수는 가장 작은 id(가장 왼쪽 단말 노드의 시작)의 위치를 반환합니다.

```diff
+Cursor* table_start(Table* table) {
+  Cursor* cursor =  table_find(table, 0);
+
+  void* node = get_page(table->pager, cursor->page_num);
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  cursor->end_of_table = (num_cells == 0);
+
+  return cursor;
+}
```

변경작업에도 불구하고 한 노드의 행들만 출력됩니다.

```
db > select
(1, user1, person1@example.com)
(2, user2, person2@example.com)
(3, user3, person3@example.com)
(4, user4, person4@example.com)
(5, user5, person5@example.com)
(6, user6, person6@example.com)
(7, user7, person7@example.com)
Executed.
db >
```

15개 행을 갖는 B-트리는 하나의 내부 노드와 두 개의 단말 노드로 구성되며, 다음과 같은 구조를 갖습니다.

{% include image.html url="assets/images/btree3.png" description="우리의 B-트리 구조" %}

전체 테이블을 스캔하기 위해서는 첫 단말 노드의 끝에 도달한 후 두 번째 단말 노드로 이동해야 합니다. 이를 위해, 단말 노드 헤더에 "next_leaf" 필드를 추가하겠습니다. 이 필드는 오른쪽 형제 노드의 페이지 번호를 갖습니다. 가장 오른쪽의 단말 노드는 형제가 없음을 표시하기 위해 0의 `next_leaf` 값(페이지 0은 테이블의 루트 노드 용으로 예약된 값)을 갖습니다.

단말 노드 헤더 형식을 수정하여 새로운 필드를 포함시킵니다.

```diff
 const uint32_t LEAF_NODE_NUM_CELLS_SIZE = sizeof(uint32_t);
 const uint32_t LEAF_NODE_NUM_CELLS_OFFSET = COMMON_NODE_HEADER_SIZE;
-const uint32_t LEAF_NODE_HEADER_SIZE =
-    COMMON_NODE_HEADER_SIZE + LEAF_NODE_NUM_CELLS_SIZE;
+const uint32_t LEAF_NODE_NEXT_LEAF_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_NEXT_LEAF_OFFSET =
+    LEAF_NODE_NUM_CELLS_OFFSET + LEAF_NODE_NUM_CELLS_SIZE;
+const uint32_t LEAF_NODE_HEADER_SIZE = COMMON_NODE_HEADER_SIZE +
+                                       LEAF_NODE_NUM_CELLS_SIZE +
+                                       LEAF_NODE_NEXT_LEAF_SIZE;
 
 ```

새 필드에 접근하는 함수도 추가합니다.
```diff
+uint32_t* leaf_node_next_leaf(void* node) {
+  return node + LEAF_NODE_NEXT_LEAF_OFFSET;
+}
```

새 단말 노드를 초기화할 때, 기본적으로 `next_leaf` 를 0으로 설정합니다.

```diff
@@ -322,6 +330,7 @@ void initialize_leaf_node(void* node) {
   set_node_type(node, NODE_LEAF);
   set_node_root(node, false);
   *leaf_node_num_cells(node) = 0;
+  *leaf_node_next_leaf(node) = 0;  // 0 는 형제가 없음을 의미합니다.
 }
```

단말 노드를 분할할 때마다 형제 노드 포인터를 갱신합니다. 기존 단말 노드의 형제 노드는 새로운 단말 노드가 되고, 새 단말 노드의 형제는 기존 노드의 형제였던 노드가 됩니다.

```diff
@@ -659,6 +671,8 @@ void leaf_node_split_and_insert(Cursor* cursor, uint32_t key, Row* value) {
   uint32_t new_page_num = get_unused_page_num(cursor->table->pager);
   void* new_node = get_page(cursor->table->pager, new_page_num);
   initialize_leaf_node(new_node);
+  *leaf_node_next_leaf(new_node) = *leaf_node_next_leaf(old_node);
+  *leaf_node_next_leaf(old_node) = new_page_num;
```

새 필드 추가로 몇 가지 상수 값들이 바뀝니다.
```diff
   it 'prints constants' do
     script = [
       ".constants",
@@ -199,9 +228,9 @@ describe 'database' do
       "db > Constants:",
       "ROW_SIZE: 293",
       "COMMON_NODE_HEADER_SIZE: 6",
-      "LEAF_NODE_HEADER_SIZE: 10",
+      "LEAF_NODE_HEADER_SIZE: 14",
       "LEAF_NODE_CELL_SIZE: 297",
-      "LEAF_NODE_SPACE_FOR_CELLS: 4086",
+      "LEAF_NODE_SPACE_FOR_CELLS: 4082",
       "LEAF_NODE_MAX_CELLS: 13",
       "db > ",
     ])
```

이제 단말 노드의 끝에서 커서를 진행하는 경우, 단말 노드가 형제 노드를 갖는지 확인해야 합니다. 형제가 있으면 이동하고, 없으면 테이블의 끝임을 표시합니다.

```diff
@@ -428,7 +432,15 @@ void cursor_advance(Cursor* cursor) {
 
   cursor->cell_num += 1;
   if (cursor->cell_num >= (*leaf_node_num_cells(node))) {
-    cursor->end_of_table = true;
+    /* 다음 단말 노드로 진행 */
+    uint32_t next_page_num = *leaf_node_next_leaf(node);
+    if (next_page_num == 0) {
+      /* 최우측 단말 노드 */
+      cursor->end_of_table = true;
+    } else {
+      cursor->page_num = next_page_num;
+      cursor->cell_num = 0;
+    }
   }
 }
```

변경을 통해 실제로 15개의 행이 출력이 되는데...
```
db > select
(1, user1, person1@example.com)
(2, user2, person2@example.com)
(3, user3, person3@example.com)
(4, user4, person4@example.com)
(5, user5, person5@example.com)
(6, user6, person6@example.com)
(7, user7, person7@example.com)
(8, user8, person8@example.com)
(9, user9, person9@example.com)
(10, user10, person10@example.com)
(11, user11, person11@example.com)
(12, user12, person12@example.com)
(13, user13, person13@example.com)
(1919251317, 14, on14@example.com)
(15, user15, person15@example.com)
Executed.
db >
```

...한 행이 이상합니다.
```
(1919251317, 14, on14@example.com)
```

디버깅을 통해, 필자는 노드 분할 과정에서 버그 때문임을 찾아냈습니다.

```diff
@@ -676,7 +690,9 @@ void leaf_node_split_and_insert(Cursor* cursor, uint32_t key, Row* value) {
     void* destination = leaf_node_cell(destination_node, index_within_node);
 
     if (i == cursor->cell_num) {
-      serialize_row(value, destination);
+      serialize_row(value,
+                    leaf_node_value(destination_node, index_within_node));
+      *leaf_node_key(destination_node, index_within_node) = key;
     } else if (i > cursor->cell_num) {
       memcpy(destination, leaf_node_cell(old_node, i - 1), LEAF_NODE_CELL_SIZE);
     } else {
```

단말 노드의 각 셀은 키, 그다음 값으로 구성되어 있음을 기억하기 바랍니다.

{% include image.html url="assets/images/leaf-node-format.png" description="단말 노드 형식" %}

우리는 새로운 행(값)을 키가 저장되어야 할 셀의 시작 부분에 쓰고 있었습니다. 즉, 사용자 이름의 일부가 id 구역에 쓰인 것입니다. (따라서 엄청나게 큰 id가 출력 되었습니다.)

버그를 고친 후, 마침내 예상대로 테이블 전체를 출력합니다.

```
db > select
(1, user1, person1@example.com)
(2, user2, person2@example.com)
(3, user3, person3@example.com)
(4, user4, person4@example.com)
(5, user5, person5@example.com)
(6, user6, person6@example.com)
(7, user7, person7@example.com)
(8, user8, person8@example.com)
(9, user9, person9@example.com)
(10, user10, person10@example.com)
(11, user11, person11@example.com)
(12, user12, person12@example.com)
(13, user13, person13@example.com)
(14, user14, person14@example.com)
(15, user15, person15@example.com)
Executed.
db >
```

휴! 버그가 속속 생기지만 그래도 잘 진행되고 있습니다. 

그럼 다음 장에서 뵙겠습니다.
