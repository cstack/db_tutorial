---
title: 제10 장 - 단말 노드 분할
date: 2017-10-09
---

우리의 B-트리는 오직 단일 노드로 구성된 탓에 트리처럼 느껴지지 않습니다. 이 문제를 해결하기 위해서는 단말 노드를 둘로 나누는 코드가 필요합니다. 그다음, 두 단말 노드의 부모 노드가 될 내부 노드를 생성해야 합니다.

기본적으로 이번 장의 목표는 아래 그림에서

{% include image.html url="assets/images/btree2.png" description="단일 노드 B-트리" %}

다음과 같이 되는 것입니다.

{% include image.html url="assets/images/btree3.png" description="레벨 2 B-트리" %}

무엇보다 먼저, 가득 찬 단말 노드에 대한 에러 처리를 삭제하겠습니다.

```diff
 void leaf_node_insert(Cursor* cursor, uint32_t key, Row* value) {
   void* node = get_page(cursor->table->pager, cursor->page_num);
 
   uint32_t num_cells = *leaf_node_num_cells(node);
   if (num_cells >= LEAF_NODE_MAX_CELLS) {
     // Node full
-    printf("Need to implement splitting a leaf node.\n");
-    exit(EXIT_FAILURE);
+    leaf_node_split_and_insert(cursor, key, value);
+    return;
   }
```

```diff
ExecuteResult execute_insert(Statement* statement, Table* table) {
   void* node = get_page(table->pager, table->root_page_num);
   uint32_t num_cells = (*leaf_node_num_cells(node));
-  if (num_cells >= LEAF_NODE_MAX_CELLS) {
-    return EXECUTE_TABLE_FULL;
-  }
 
   Row* row_to_insert = &(statement->row_to_insert);
   uint32_t key_to_insert = row_to_insert->id;
```

## 분할 알고리즘

쉬운 것들은 모두 끝났습니다. 여기 [SQLite Database System: Design and Implementation](https://play.google.com/store/books/details/Sibsankar_Haldar_SQLite_Database_System_Design_and?id=9Z6IQQnX1JEC&hl=en) 으로부터 가져온 우리가 해야 할 작업에 대한 설명입니다.

> 단말 노드에 공간이 없다면, 노드가 갖고 있는 기존 셀들과 새로운 셀(추가될)을 상부와 하부로 반반 나눕니다. (상부에 있는 키들은 하부의 키들보다 커야 합니다.) 우리는 새로운 단말 노드를 할당하고, 기존 노드의 상부를 새 노드로 옮기는 방식으로 구현합니다.


기존 노드를 가져오고 새 노드를 생성해봅시다.

```diff
+void leaf_node_split_and_insert(Cursor* cursor, uint32_t key, Row* value) {
+  /*
+  새 노드를 생성하고 절반의 셀을 이동합니다.
+  두 노드 중 하나에 새 값을 삽입합니다.
+  부모 노드를 갱신하거나 새로운 부모 노드를 생성합니다.
+  */
+
+  void* old_node = get_page(cursor->table->pager, cursor->page_num);
+  uint32_t new_page_num = get_unused_page_num(cursor->table->pager);
+  void* new_node = get_page(cursor->table->pager, new_page_num);
+  initialize_leaf_node(new_node);
```

다음으로, 모든 셀들을 적절한 위치에 복사합니다.

```diff
+  /*
+  기존 노드의 모든 키들과 새 키를 기존 노드(좌측)와 
+  새 노드(우측)에 균일하게 나눕니다.
+  기존 노드의 우측부터 시작하여, 각 키를 올바른 위치로 이동합니다.
+  */
+  for (int32_t i = LEAF_NODE_MAX_CELLS; i >= 0; i--) {
+    void* destination_node;
+    if (i >= LEAF_NODE_LEFT_SPLIT_COUNT) {
+      destination_node = new_node;
+    } else {
+      destination_node = old_node;
+    }
+    uint32_t index_within_node = i % LEAF_NODE_LEFT_SPLIT_COUNT;
+    void* destination = leaf_node_cell(destination_node, index_within_node);
+
+    if (i == cursor->cell_num) {
+      serialize_row(value, destination);
+    } else if (i > cursor->cell_num) {
+      memcpy(destination, leaf_node_cell(old_node, i - 1), LEAF_NODE_CELL_SIZE);
+    } else {
+      memcpy(destination, leaf_node_cell(old_node, i), LEAF_NODE_CELL_SIZE);
+    }
+  }
```

각 노드의 헤더에서 셀 개수 필드를 갱신합니다.

```diff
+  /* 각 단말 노드의 셀 개수 갱신 */
+  *(leaf_node_num_cells(old_node)) = LEAF_NODE_LEFT_SPLIT_COUNT;
+  *(leaf_node_num_cells(new_node)) = LEAF_NODE_RIGHT_SPLIT_COUNT;
```

그런 다음 노드의 부모 노드를 갱신해야 합니다. 기존 노드가 루트인 경우 부모를 갖고 있지 않습니다. 이 경우 부모 노드 역할을 수행할 새 루트 노드를 생성합니다. 우선 분기문에 스텁을 사용하겠습니다.

```diff
+  if (is_node_root(old_node)) {
+    return create_new_root(cursor->table, new_page_num);
+  } else {
+    printf("Need to implement updating parent after split\n");
+    exit(EXIT_FAILURE);
+  }
+}
```

## 새로운 페이지 할당

다시 돌아가서 몇 가지 새로운 함수와 상수를 정의하겠습니다. 우리는 새로운 단말 노드를 생성할 때, `get_unused_page_num()`에 의해 결정된 페이지에 넣을 것입니다.

```diff
+/*
+페이지 재 사용을 시작하기 전까지 항상 새 페이지는
+데이터베이스 파일 끝에 저장됩니다.
+*/
+uint32_t get_unused_page_num(Pager* pager) { return pager->num_pages; }
```

현재 N 개 페이지가 있는 데이터베이스는 0번부터 N-1 번까지의 페이지가 할당되었다고 가정합니다. 그러므로 새로운 페이지를 위해서 항상 N 번 페이지를 할당하게 됩니다. 우리가 최종적으로 삭제 연산 구현을 마친 후에는, 몇몇 페이지는 빈 공간이 될 것이며 해당 페이지 번호를 사용하지 않게 됩니다. 우리는 효율을 위해서 빈 공간을 재사용 할 수 있습니다.

## 단말 노드 크기

트리의 균형을 유지하기 위해, 두 개의 새로운 노드에 셀들을 균등하게 분배하였습니다. 단말 노드가 N 개의 셀을 갖는 경우, N+1개의 셀들(N 개의 기존 셀과 하나의 새로운 셀)을 두 노드에 분배해야 합니다. 필자는 N+1이 홀수인 경우 왼쪽 노드가 한 개의 셀을 더 갖도록 선택했습니다.

```diff
+const uint32_t LEAF_NODE_RIGHT_SPLIT_COUNT = (LEAF_NODE_MAX_CELLS + 1) / 2;
+const uint32_t LEAF_NODE_LEFT_SPLIT_COUNT =
+    (LEAF_NODE_MAX_CELLS + 1) - LEAF_NODE_RIGHT_SPLIT_COUNT;
```

## 새로운 루트 노드 생성

[SQLite Database System](https://play.google.com/store/books/details/Sibsankar_Haldar_SQLite_Database_System_Design_and?id=9Z6IQQnX1JEC&hl=en) 는 새로운 루트 노드를 만드는 과정을 다음과 같이 설명하였습니다.

> N을 루트 노드라고 하겠습니다. 먼저 두 개의 노드 L과 R을 할당합니다. N의 하부를 L로, 상부를 R로 이동합니다. 이제 N은 비어 있게 됩니다. 〈L, K,R〉 을 N에 추가합니다. K는 L에서 최대 키 값입니다. 페이지 N은 루트 노드로 남습니다. 트리의 깊이가 1 증가했지만, 새로운 트리는 B+ 트리 특성을 위반하지 않고 높이 균형을 유지한다는 점에 유의하기 바랍니다.

우리는 이미 우측 자식 노드를 할당하고 상부를 옮기는 작업을 마쳤습니다. 우리의 함수는 우측 자식 노드를 입력받고 왼쪽 자식 노드를 저장할 새로운 페이지를 할당합니다.

```diff
+void create_new_root(Table* table, uint32_t right_child_page_num) {
+  /*
+  루트 노드 분할 작업을 수행합니다.
+  기존 루트 노드는 새 페이지에 복사되어 왼쪽 자식 노드가 됩니다.
+  함수는 우측 자식 노드의 주소(페이지 번호)를 매개변수로 받습니다.
+  루트 페이지가 새로운 루트 노드를 갖도록 재 설정합니다.
+  새 루트 노드는 두 개의 자식 노드를 갖습니다.
+  */
+
+  void* root = get_page(table->pager, table->root_page_num);
+  void* right_child = get_page(table->pager, right_child_page_num);
+  uint32_t left_child_page_num = get_unused_page_num(table->pager);
+  void* left_child = get_page(table->pager, left_child_page_num);
```

기존 루트 노드는 왼쪽 자식에 복사되며, 루트 페이지를 재사용 할 수 있게 됩니다.

```diff
+  /* 왼쪽 자식에 기존 루트 노드의 복사 데이터가 있습니다. */
+  memcpy(left_child, root, PAGE_SIZE);
+  set_node_root(left_child, false);
```

마지막으로 루트 페이지를 두 개의 자식 노드를 갖는 내부 노드로 초기화합니다.

```diff
+  /* 루트 노드는 하나의 키와 두 개의 자식을 갖는 새로운 내부 노드입니다. */
+  initialize_internal_node(root);
+  set_node_root(root, true);
+  *internal_node_num_keys(root) = 1;
+  *internal_node_child(root, 0) = left_child_page_num;
+  uint32_t left_child_max_key = get_node_max_key(left_child);
+  *internal_node_key(root, 0) = left_child_max_key;
+  *internal_node_right_child(root) = right_child_page_num;
+}
```

## 내부 노드 형식

드디어 내부 노드를 만들게 되었으니, 노드의 형식 정의가 필요합니다. 내부 노드는 공통 헤더로 시작하고, 그다음에 갖고 있는 키의 수, 그리고 최우측 자식 노드의 페이지 번호를 갖습니다. 내부 노드는 항상 갖고 있는 키보다 한 개 많은 자식 노드 포인터를 갖습니다. 그 여분의 자식 노드 포인터(최우측 자식 노드 포인터)는 헤더에 저장됩니다.

```diff
+/*
+ * 내부 노드 헤더 형식
+ */
+const uint32_t INTERNAL_NODE_NUM_KEYS_SIZE = sizeof(uint32_t);
+const uint32_t INTERNAL_NODE_NUM_KEYS_OFFSET = COMMON_NODE_HEADER_SIZE;
+const uint32_t INTERNAL_NODE_RIGHT_CHILD_SIZE = sizeof(uint32_t);
+const uint32_t INTERNAL_NODE_RIGHT_CHILD_OFFSET =
+    INTERNAL_NODE_NUM_KEYS_OFFSET + INTERNAL_NODE_NUM_KEYS_SIZE;
+const uint32_t INTERNAL_NODE_HEADER_SIZE = COMMON_NODE_HEADER_SIZE +
+                                           INTERNAL_NODE_NUM_KEYS_SIZE +
+                                           INTERNAL_NODE_RIGHT_CHILD_SIZE;
```

몸체는 자식 노드 포인터와 키를 포함하고 있는 셀들의 배열입니다. 모든 키는 왼쪽 자식 노드의 최대 키가 됩니다.

```diff
+/*
+ * 내부 노드 몸체 형식
+ */
+const uint32_t INTERNAL_NODE_KEY_SIZE = sizeof(uint32_t);
+const uint32_t INTERNAL_NODE_CHILD_SIZE = sizeof(uint32_t);
+const uint32_t INTERNAL_NODE_CELL_SIZE =
+    INTERNAL_NODE_CHILD_SIZE + INTERNAL_NODE_KEY_SIZE;
```

정의한 상수들을 바탕으로, 내부 노드는 다음과 같은 형식을 갖습니다.

{% include image.html url="assets/images/internal-node-format.png" description="우리의 내부 노드 형식" %}

많은 분기 계수(branching factor)에 주목하기 바랍니다. 우리의 내부 노드는 자식 노드 포인터와 키 쌍의 크기가 아주 작기 때문에 각 내부 노드마다 510개 키와 511개 포인터를 저장할 수 있습니다. 이는 주어진 키값을 찾기 위해 많은 층을 순회할 필요가 없다는 것을 의미합니다!

| # 내부 노드 층         | 최대 # 단말 노드    | 모든 단말 노드의 크기  |
|------------------------|---------------------|------------------------|
| 0                      | 511^0 = 1           | 4 KB                   |
| 1                      | 511^1 = 512         | ~2 MB                  |
| 2                      | 511^2 = 261,121     | ~1 GB                  |
| 3                      | 511^3 = 133,432,831 | ~550 GB                |

실제로, 헤더, 키 그리고 낭비되는 공간 때문에 단말 노드 당 4KB의 데이터를 저장할 순 없습니다. 하지만 디스크에서 단 4페이지를 로드함으로써, 500GB 정도의 데이터를 탐색할 수 있게 됩니다. 이것이 데이터베이스에 B-트리가 유용한 이유입니다.

다음은 내부 노드를 읽고 쓰기 위한 함수들입니다.

```diff
+uint32_t* internal_node_num_keys(void* node) {
+  return node + INTERNAL_NODE_NUM_KEYS_OFFSET;
+}
+
+uint32_t* internal_node_right_child(void* node) {
+  return node + INTERNAL_NODE_RIGHT_CHILD_OFFSET;
+}
+
+uint32_t* internal_node_cell(void* node, uint32_t cell_num) {
+  return node + INTERNAL_NODE_HEADER_SIZE + cell_num * INTERNAL_NODE_CELL_SIZE;
+}
+
+uint32_t* internal_node_child(void* node, uint32_t child_num) {
+  uint32_t num_keys = *internal_node_num_keys(node);
+  if (child_num > num_keys) {
+    printf("Tried to access child_num %d > num_keys %d\n", child_num, num_keys);
+    exit(EXIT_FAILURE);
+  } else if (child_num == num_keys) {
+    return internal_node_right_child(node);
+  } else {
+    return internal_node_cell(node, child_num);
+  }
+}
+
+uint32_t* internal_node_key(void* node, uint32_t key_num) {
+  return internal_node_cell(node, key_num) + INTERNAL_NODE_CHILD_SIZE;
+}
```

내부 노드의 경우, 최대 키는 항상 우측 키입니다.
단말 노드의 경우는, 가장 큰 인덱스의 키입니다.

```diff
+uint32_t get_node_max_key(void* node) {
+  switch (get_node_type(node)) {
+    case NODE_INTERNAL:
+      return *internal_node_key(node, *internal_node_num_keys(node) - 1);
+    case NODE_LEAF:
+      return *leaf_node_key(node, *leaf_node_num_cells(node) - 1);
+  }
+}
```

## 루트 추적

드디어 공통 노드 헤더의 `is_root` 필드를 사용합니다. 단말 노드를 분할하는 방법을 결정하는 데 사용한다는 점을 상기하기 바립니다.

```c
  if (is_node_root(old_node)) {
    return create_new_root(cursor->table, new_page_num);
  } else {
    printf("Need to implement updating parent after split\n");
    exit(EXIT_FAILURE);
  }
}
```

게터와 세터는 다음과 같습니다.

```diff
+bool is_node_root(void* node) {
+  uint8_t value = *((uint8_t*)(node + IS_ROOT_OFFSET));
+  return (bool)value;
+}
+
+void set_node_root(void* node, bool is_root) {
+  uint8_t value = is_root;
+  *((uint8_t*)(node + IS_ROOT_OFFSET)) = value;
+}
```


두 노드 유형의 초기화는 기본적으로 'is_root' 를 false로 설정합니다.

```diff
 void initialize_leaf_node(void* node) {
   set_node_type(node, NODE_LEAF);
+  set_node_root(node, false);
   *leaf_node_num_cells(node) = 0;
 }

+void initialize_internal_node(void* node) {
+  set_node_type(node, NODE_INTERNAL);
+  set_node_root(node, false);
+  *internal_node_num_keys(node) = 0;
+}
```

테이블의 첫 번째 노드를 만들 때는 `is_root` 를 true로 설정해야 합니다.

```diff
     // 새 데이터베이스 파일. 페이지 0을 단말 노드로 초기화합니다.
     void* root_node = get_page(pager, 0);
     initialize_leaf_node(root_node);
+    set_node_root(root_node, true);
   }
 
   return table;
```

## 트리 출력

데이터베이스의 상태를 시각화할 수 있도록 다중 레벨 트리를 출력하는 `.btree` 메타 명령을 추가합니다.

현재의 `print_leaf_node()` 를

```diff
-void print_leaf_node(void* node) {
-  uint32_t num_cells = *leaf_node_num_cells(node);
-  printf("leaf (size %d)\n", num_cells);
-  for (uint32_t i = 0; i < num_cells; i++) {
-    uint32_t key = *leaf_node_key(node, i);
-    printf("  - %d : %d\n", i, key);
-  }
-}
```

노드를 입력받아 그 자식들을 출력하는 새로운 재귀 함수로 대체하겠습니다. 이 재귀 함수는 들여쓰기 정도를 매개변수로 받으며, 재귀 호출에 따라 정도가 증가합니다. 추가로 들여 쓰기를 위한 작은 헬퍼 함수를 추가합니다.

```diff
+void indent(uint32_t level) {
+  for (uint32_t i = 0; i < level; i++) {
+    printf("  ");
+  }
+}
+
+void print_tree(Pager* pager, uint32_t page_num, uint32_t indentation_level) {
+  void* node = get_page(pager, page_num);
+  uint32_t num_keys, child;
+
+  switch (get_node_type(node)) {
+    case (NODE_LEAF):
+      num_keys = *leaf_node_num_cells(node);
+      indent(indentation_level);
+      printf("- leaf (size %d)\n", num_keys);
+      for (uint32_t i = 0; i < num_keys; i++) {
+        indent(indentation_level + 1);
+        printf("- %d\n", *leaf_node_key(node, i));
+      }
+      break;
+    case (NODE_INTERNAL):
+      num_keys = *internal_node_num_keys(node);
+      indent(indentation_level);
+      printf("- internal (size %d)\n", num_keys);
+      for (uint32_t i = 0; i < num_keys; i++) {
+        child = *internal_node_child(node, i);
+        print_tree(pager, child, indentation_level + 1);
+
+        indent(indentation_level + 1);
+        printf("- key %d\n", *internal_node_key(node, i));
+      }
+      child = *internal_node_right_child(node);
+      print_tree(pager, child, indentation_level + 1);
+      break;
+  }
+}
```

그리고 0의 들여쓰기 정도를 매개 변수로 입력하여 출력 함수 호출 부를 수정합니다.

```diff
   } else if (strcmp(input_buffer->buffer, ".btree") == 0) {
     printf("Tree:\n");
-    print_leaf_node(get_page(table->pager, 0));
+    print_tree(table->pager, 0, 0);
     return META_COMMAND_SUCCESS;
```

다음은 새 출력 기능을 위한 새로운 테스트 케이스입니다!

```diff
+  it 'allows printing out the structure of a 3-leaf-node btree' do
+    script = (1..14).map do |i|
+      "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << ".btree"
+    script << "insert 15 user15 person15@example.com"
+    script << ".exit"
+    result = run_script(script)
+
+    expect(result[14...(result.length)]).to match_array([
+      "db > Tree:",
+      "- internal (size 1)",
+      "  - leaf (size 7)",
+      "    - 1",
+      "    - 2",
+      "    - 3",
+      "    - 4",
+      "    - 5",
+      "    - 6",
+      "    - 7",
+      "  - key 7",
+      "  - leaf (size 7)",
+      "    - 8",
+      "    - 9",
+      "    - 10",
+      "    - 11",
+      "    - 12",
+      "    - 13",
+      "    - 14",
+      "db > 내부 노드 탐색 구현이 필요합니다.",
+    ])
+  end
```

새로운 출력 형식이 약간 단순화되었으므로 기존의 `.btree` 테스트를 수정해야 합니다.

```diff
       "db > Executed.",
       "db > Executed.",
       "db > Tree:",
-      "leaf (size 3)",
-      "  - 0 : 1",
-      "  - 1 : 2",
-      "  - 2 : 3",
+      "- leaf (size 3)",
+      "  - 1",
+      "  - 2",
+      "  - 3",
       "db > "
     ])
   end
```

새로운 테스트의 `.btree` 출력은 다음과 같습니다.

```
Tree:
- internal (size 1)
  - leaf (size 7)
    - 1
    - 2
    - 3
    - 4
    - 5
    - 6
    - 7
  - key 7
  - leaf (size 7)
    - 8
    - 9
    - 10
    - 11
    - 12
    - 13
    - 14
```

최소 들여쓰기 정도에서 루트 노드(내부 노드)가 보입니다. 키가 하나이므로 `size 1` 을 출력합니다. 다음 들여 쓰기에서 하나의 단말 노드와 하나의 키 그리고 또 다른 단말 노드가 보입니다. 루트 노드의 키(7)는 첫 번째 노드의 최대 키값입니다. 7보다 큰 모든 키는 두 번째 단말 노드에 위치합니다.

## 주요 문제

여기까지 잘 따라왔다면 우리가 뭔가 큰 것을 놓쳤다는 것을 알아차릴 수 있을 것입니다. 행을 하나 더 삽입하는 경우 어떻게 되는지 보시기 바랍니다.

```
db > insert 15 user15 person15@example.com
내부 노드 탐색 구현이 필요합니다.
```

이런! 누가 TODO 메시지를 썼죠? :P

다음 장에서 다중 레벨 트리에 대한 구현을 통해 B-트리에 대한 여정을 계속 진행하겠습니다.
