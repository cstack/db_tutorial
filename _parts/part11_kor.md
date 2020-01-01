---
title: 제11 장 - B-트리 재귀 탐색
date: 2017-10-22
---

지난 장에서 15번째 행 삽입 오류와 함께 끝이 났었습니다.

```
db > insert 15 user15 person15@example.com
내부 노드 탐색 구현이 필요합니다.
```

먼저 코드 스텁을 새 함수 호출로 변경합니다.

```diff
   if (get_node_type(root_node) == NODE_LEAF) {
     return leaf_node_find(table, root_page_num, key);
   } else {
-    printf("Need to implement searching an internal node\n");
-    exit(EXIT_FAILURE);
+    return internal_node_find(table, root_page_num, key);
   }
 }
```

이 함수는 주어진 키를 갖는 자식 노드를 찾기 위해 이진 탐색을 수행합니다. 각 자식 노드 포인터 오른쪽에 위치한 키가 자식 노드가 갖는 최대 키임을 명심하기 바랍니다.

{% include image.html url="assets/images/btree6.png" description="레벨3 B-트리" %}

따라서 우리의 이진 탐색은 찾을 키와 자식 노드 포인터 오른쪽에 있는 키를 비교합니다.

```diff
+Cursor* internal_node_find(Table* table, uint32_t page_num, uint32_t key) {
+  void* node = get_page(table->pager, page_num);
+  uint32_t num_keys = *internal_node_num_keys(node);
+
+  /* 이진 탐색으로 탐색할 자식의 인덱스를 찾습니다. */
+  uint32_t min_index = 0;
+  uint32_t max_index = num_keys; /* 키 개수 + 1 개의 자식 노드가 있습니다. */
+
+  while (min_index != max_index) {
+    uint32_t index = (min_index + max_index) / 2;
+    uint32_t key_to_right = *internal_node_key(node, index);
+    if (key_to_right >= key) {
+      max_index = index;
+    } else {
+      min_index = index + 1;
+    }
+  }
```

또한 내부 노드의 자식 노드는 단말 노드이거나 내부 노드 일 수 있습니다. 따라서 올바른 자식 노드를 찾은 후 유형에 맞는 적절한 탐색 함수를 호출합니다.

```diff
+  uint32_t child_num = *internal_node_child(node, min_index);
+  void* child = get_page(table->pager, child_num);
+  switch (get_node_type(child)) {
+    case NODE_LEAF:
+      return leaf_node_find(table, child_num, key);
+    case NODE_INTERNAL:
+      return internal_node_find(table, child_num, key);
+  }
+}
```

# 테스트

이제 다중 노드 B-트리에 키를 삽입해도 더 이상 오류가 발생하지 않을 것입니다. 따라서 다음과 같이 테스트를 수정합니다.

```diff
       "    - 12",
       "    - 13",
       "    - 14",
-      "db > Need to implement searching an internal node",
+      "db > Executed.",
+      "db > ",
     ])
   end
```

추가로 다른 테스트를 해보는 게 좋을 것 같습니다. 이번에는 1400개 행을 삽입해보겠습니다. 수행 결과 에러가 발생하지만, 새로운 에러 메시지가 보입니다. 현재 우리의 테스트 코드가 프로그램이 충돌로 망가지는 경우 잘 처리하지 못하는 것으로 보입니다. 이렇게 된 이상 충돌 전까지의 출력만 사용하겠습니다.

```diff
     raw_output = nil
     IO.popen("./db test.db", "r+") do |pipe|
       commands.each do |command|
-        pipe.puts command
+        begin
+          pipe.puts command
+        rescue Errno::EPIPE
+          break
+        end
       end

       pipe.close_write
```

그 결과 1400 행 테스트에서 다음과 같은 에러 출력을 얻게 됩니다.

```diff
     end
     script << ".exit"
     result = run_script(script)
-    expect(result[-2]).to eq('db > Error: Table full.')
+    expect(result.last(2)).to match_array([
+      "db > Executed.",
+      "db > Need to implement updating parent after split",
+    ])
   end
```

우리의 다음 작업이 되겠습니다!

