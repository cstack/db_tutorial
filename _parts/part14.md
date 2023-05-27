---
title: Part 14 - Splitting Internal Nodes
date: 2023-05-23
---

The next leg of our journey will be splitting internal nodes which are unable to accommodate new keys. Consider the example below:

{% include image.html url="assets/images/splitting-internal-node.png" description="Example of splitting an internal" %}

In this example, we add the key "11" to the tree. This will cause our root to split. When splitting an internal node, we will have to do a few things in order to keep everything straight:

1. Create a sibling node to store (n-1)/2 of the original node's keys
2. Move these keys from the original node to the sibling node
3. Update the original node's key in the parent to reflect its new max key after splitting
4. Insert the sibling node into the parent (could result in the parent also being split)

We will begin by replacing our stub code with the call to `internal_node_split_and_insert`

```diff
+void internal_node_split_and_insert(Table* table, uint32_t parent_page_num,
+                          uint32_t child_page_num);
+
 void internal_node_insert(Table* table, uint32_t parent_page_num,
                           uint32_t child_page_num) {
   /*
@@ -685,25 +714,39 @@ void internal_node_insert(Table* table, uint32_t parent_page_num,
 
   void* parent = get_page(table->pager, parent_page_num);
   void* child = get_page(table->pager, child_page_num);
-  uint32_t child_max_key = get_node_max_key(child);
+  uint32_t child_max_key = get_node_max_key(table->pager, child);
   uint32_t index = internal_node_find_child(parent, child_max_key);
 
   uint32_t original_num_keys = *internal_node_num_keys(parent);
-  *internal_node_num_keys(parent) = original_num_keys + 1;
 
   if (original_num_keys >= INTERNAL_NODE_MAX_CELLS) {
-    printf("Need to implement splitting internal node\n");
-    exit(EXIT_FAILURE);
+    internal_node_split_and_insert(table, parent_page_num, child_page_num);
+    return;
   }
 
   uint32_t right_child_page_num = *internal_node_right_child(parent);
+  /*
+  An internal node with a right child of INVALID_PAGE_NUM is empty
+  */
+  if (right_child_page_num == INVALID_PAGE_NUM) {
+    *internal_node_right_child(parent) = child_page_num;
+    return;
+  }
+
   void* right_child = get_page(table->pager, right_child_page_num);
+  /*
+  If we are already at the max number of cells for a node, we cannot increment
+  before splitting. Incrementing without inserting a new key/child pair
+  and immediately calling internal_node_split_and_insert has the effect
+  of creating a new key at (max_cells + 1) with an uninitialized value
+  */
+  *internal_node_num_keys(parent) = original_num_keys + 1;
 
-  if (child_max_key > get_node_max_key(right_child)) {
+  if (child_max_key > get_node_max_key(table->pager, right_child)) {
     /* Replace right child */
     *internal_node_child(parent, original_num_keys) = right_child_page_num;
     *internal_node_key(parent, original_num_keys) =
-        get_node_max_key(right_child);
+        get_node_max_key(table->pager, right_child);
     *internal_node_right_child(parent) = child_page_num;
```

There are three important changes we are making here aside from replacing the stub:
 - First, `internal_node_split_and_insert` is forward-declared because we will be calling `internal_node_insert` in its definition to avoid code duplication.
 - In addition, we are moving the logic which increments the parent's number of keys further down in the function definition to ensure that this does not happen before the split.
 - Finally, we are ensuring that a child node inserted into an empty internal node will become that internal node's right child without any other operations being performed, since an empty internal node has no keys to manipulate. 

The changes above require that we be able to identify an empty node - to this end, we will first define a constant which represents an invalid page number that is the child of every empty node.

```diff
+#define INVALID_PAGE_NUM UINT32_MAX
```
Now, when an internal node is initialized, we initialize its right child with this invalid page number.

```diff
@@ -330,6 +335,12 @@ void initialize_internal_node(void* node) {
   set_node_type(node, NODE_INTERNAL);
   set_node_root(node, false);
   *internal_node_num_keys(node) = 0;
+  /*
+  Necessary because the root page number is 0; by not initializing an internal 
+  node's right child to an invalid page number when initializing the node, we may
+  end up with 0 as the node's right child, which makes the node a parent of the root
+  */
+  *internal_node_right_child(node) = INVALID_PAGE_NUM;
 }
```

This step was made necessary by a problem that the comment above attempts to summarize - when initializing an internal node without explicitly initializing the right child field, the value of that field at runtime could be 0 depending on the compiler or the architecture of the machine on which the program is being executed. Since we are using 0 as our root page number, this means that a newly allocated internal node will be a parent of the root.

We have introduced some guards in our `internal_node_child` function to throw an error in the case of an attempt to access an invalid page.

```diff
@@ -186,9 +188,19 @@ uint32_t* internal_node_child(void* node, uint32_t child_num) {
     printf("Tried to access child_num %d > num_keys %d\n", child_num, num_keys);
     exit(EXIT_FAILURE);
   } else if (child_num == num_keys) {
-    return internal_node_right_child(node);
+    uint32_t* right_child = internal_node_right_child(node);
+    if (*right_child == INVALID_PAGE_NUM) {
+      printf("Tried to access right child of node, but was invalid page\n");
+      exit(EXIT_FAILURE);
+    }
+    return right_child;
   } else {
-    return internal_node_cell(node, child_num);
+    uint32_t* child = internal_node_cell(node, child_num);
+    if (*child == INVALID_PAGE_NUM) {
+      printf("Tried to access child %d of node, but was invalid page\n", child_num);
+      exit(EXIT_FAILURE);
+    }
+    return child;
   }
 }
```

One additional guard is needed in our `print_tree` function to ensure that we do not attempt to print an empty node, as that would involve trying to access an invalid page.

```diff
@@ -294,15 +305,17 @@ void print_tree(Pager* pager, uint32_t page_num, uint32_t indentation_level) {
       num_keys = *internal_node_num_keys(node);
       indent(indentation_level);
       printf("- internal (size %d)\n", num_keys);
-      for (uint32_t i = 0; i < num_keys; i++) {
-        child = *internal_node_child(node, i);
+      if (num_keys > 0) {
+        for (uint32_t i = 0; i < num_keys; i++) {
+          child = *internal_node_child(node, i);
+          print_tree(pager, child, indentation_level + 1);
+
+          indent(indentation_level + 1);
+          printf("- key %d\n", *internal_node_key(node, i));
+        }
+        child = *internal_node_right_child(node);
         print_tree(pager, child, indentation_level + 1);
-
-        indent(indentation_level + 1);
-        printf("- key %d\n", *internal_node_key(node, i));
       }
-      child = *internal_node_right_child(node);
-      print_tree(pager, child, indentation_level + 1);
       break;
   }
 }
```

Now for the headliner, `internal_node_split_and_insert`. We will first provide it in its entirety, and then break it down by steps.

```diff
+void internal_node_split_and_insert(Table* table, uint32_t parent_page_num,
+                          uint32_t child_page_num) {
+  uint32_t old_page_num = parent_page_num;
+  void* old_node = get_page(table->pager,parent_page_num);
+  uint32_t old_max = get_node_max_key(table->pager, old_node);
+
+  void* child = get_page(table->pager, child_page_num); 
+  uint32_t child_max = get_node_max_key(table->pager, child);
+
+  uint32_t new_page_num = get_unused_page_num(table->pager);
+
+  /*
+  Declaring a flag before updating pointers which
+  records whether this operation involves splitting the root -
+  if it does, we will insert our newly created node during
+  the step where the table's new root is created. If it does
+  not, we have to insert the newly created node into its parent
+  after the old node's keys have been transferred over. We are not
+  able to do this if the newly created node's parent is not a newly
+  initialized root node, because in that case its parent may have existing
+  keys aside from our old node which we are splitting. If that is true, we
+  need to find a place for our newly created node in its parent, and we
+  cannot insert it at the correct index if it does not yet have any keys
+  */
+  uint32_t splitting_root = is_node_root(old_node);
+
+  void* parent;
+  void* new_node;
+  if (splitting_root) {
+    create_new_root(table, new_page_num);
+    parent = get_page(table->pager,table->root_page_num);
+    /*
+    If we are splitting the root, we need to update old_node to point
+    to the new root's left child, new_page_num will already point to
+    the new root's right child
+    */
+    old_page_num = *internal_node_child(parent,0);
+    old_node = get_page(table->pager, old_page_num);
+  } else {
+    parent = get_page(table->pager,*node_parent(old_node));
+    new_node = get_page(table->pager, new_page_num);
+    initialize_internal_node(new_node);
+  }
+  
+  uint32_t* old_num_keys = internal_node_num_keys(old_node);
+
+  uint32_t cur_page_num = *internal_node_right_child(old_node);
+  void* cur = get_page(table->pager, cur_page_num);
+
+  /*
+  First put right child into new node and set right child of old node to invalid page number
+  */
+  internal_node_insert(table, new_page_num, cur_page_num);
+  *node_parent(cur) = new_page_num;
+  *internal_node_right_child(old_node) = INVALID_PAGE_NUM;
+  /*
+  For each key until you get to the middle key, move the key and the child to the new node
+  */
+  for (int i = INTERNAL_NODE_MAX_CELLS - 1; i > INTERNAL_NODE_MAX_CELLS / 2; i--) {
+    cur_page_num = *internal_node_child(old_node, i);
+    cur = get_page(table->pager, cur_page_num);
+
+    internal_node_insert(table, new_page_num, cur_page_num);
+    *node_parent(cur) = new_page_num;
+
+    (*old_num_keys)--;
+  }
+
+  /*
+  Set child before middle key, which is now the highest key, to be node's right child,
+  and decrement number of keys
+  */
+  *internal_node_right_child(old_node) = *internal_node_child(old_node,*old_num_keys - 1);
+  (*old_num_keys)--;
+
+  /*
+  Determine which of the two nodes after the split should contain the child to be inserted,
+  and insert the child
+  */
+  uint32_t max_after_split = get_node_max_key(table->pager, old_node);
+
+  uint32_t destination_page_num = child_max < max_after_split ? old_page_num : new_page_num;
+
+  internal_node_insert(table, destination_page_num, child_page_num);
+  *node_parent(child) = destination_page_num;
+
+  update_internal_node_key(parent, old_max, get_node_max_key(table->pager, old_node));
+
+  if (!splitting_root) {
+    internal_node_insert(table,*node_parent(old_node),new_page_num);
+    *node_parent(new_node) = *node_parent(old_node);
+  }
+}
+
```

The first thing we need to do is create a variable to store the page number of the node we are splitting (the old node from here out). This is necessary because the page number of the old node will change if it happens to be the table's root node. We also need to remember what the node's current max is, because that value represents its key in the parent, and that key will need to be updated with the old node's new maximum after the split occurs.

```diff
+  uint32_t old_page_num = parent_page_num;
+  void* old_node = get_page(table->pager,parent_page_num);
+  uint32_t old_max = get_node_max_key(table->pager, old_node);
```

The next important step is the branching logic which depends on whether the old node is the table's root node. We will need to keep track of this value for later use; as the comment attempts to convey, we run into a problem if we do not store this information at the beginning of our function definition - if we are not splitting the root, we cannot insert our newly created sibling node into the old node's parent right away, because it does not yet contain any keys and therefore will not be placed at the right index among the other key/child pairs which may or may not already be present in the parent node.

```diff
+  uint32_t splitting_root = is_node_root(old_node);
+
+  void* parent;
+  void* new_node;
+  if (splitting_root) {
+    create_new_root(table, new_page_num);
+    parent = get_page(table->pager,table->root_page_num);
+    /*
+    If we are splitting the root, we need to update old_node to point
+    to the new root's left child, new_page_num will already point to
+    the new root's right child
+    */
+    old_page_num = *internal_node_child(parent,0);
+    old_node = get_page(table->pager, old_page_num);
+  } else {
+    parent = get_page(table->pager,*node_parent(old_node));
+    new_node = get_page(table->pager, new_page_num);
+    initialize_internal_node(new_node);
+  }
```

Once we have settled the question of splitting or not splitting the root, we begin moving keys from the old node to its sibling. We must first move the old node's right child and set its right child field to an invalid page to indicate that it is empty. Now, we loop over the old node's remaining keys, performing the following steps on each iteration:
 1. Obtain a reference to the old node's key and child at the current index
 2. Insert the child into the sibling node
 3. Update the child's parent value to point to the sibling node
 4. Decrement the old node's number of keys

```diff
+  uint32_t* old_num_keys = internal_node_num_keys(old_node);
+
+  uint32_t cur_page_num = *internal_node_right_child(old_node);
+  void* cur = get_page(table->pager, cur_page_num);
+
+  /*
+  First put right child into new node and set right child of old node to invalid page number
+  */
+  internal_node_insert(table, new_page_num, cur_page_num);
+  *node_parent(cur) = new_page_num;
+  *internal_node_right_child(old_node) = INVALID_PAGE_NUM;
+  /*
+  For each key until you get to the middle key, move the key and the child to the new node
+  */
+  for (int i = INTERNAL_NODE_MAX_CELLS - 1; i > INTERNAL_NODE_MAX_CELLS / 2; i--) {
+    cur_page_num = *internal_node_child(old_node, i);
+    cur = get_page(table->pager, cur_page_num);
+
+    internal_node_insert(table, new_page_num, cur_page_num);
+    *node_parent(cur) = new_page_num;
+
+    (*old_num_keys)--;
+  }
```

Step 4 is important, because it serves the purpose of "erasing" the key/child pair from the old node. Although we are not actually freeing the memory at that byte offset in the old node's page, by decrementing the old node's number of keys we are making that memory location inaccessible, and the bytes will be overwritten the next time a child is inserted into the old node.

Also note the behavior of our loop invariant - if our maximum number of internal node keys changes in the future, our logic ensures that both our old node and our sibling node will end up with (n-1)/2 keys after the split, with the 1 remaining node going to the parent. If an even number is chosen as the maximum number of nodes, n/2 nodes will remain with the old node while (n-1)/2 will be moved to the sibling node. This logic would be straightforward to revise as needed.

Once the keys to be moved have been, we set the old node's i'th child as its right child and decrement its number of keys.

```diff
+  /*
+  Set child before middle key, which is now the highest key, to be node's right child,
+  and decrement number of keys
+  */
+  *internal_node_right_child(old_node) = *internal_node_child(old_node,*old_num_keys - 1);
+  (*old_num_keys)--;
```

We then insert the child node into either the old node or the sibling node depending on the value of its max key.

```diff
+  uint32_t max_after_split = get_node_max_key(table->pager, old_node);
+
+  uint32_t destination_page_num = child_max < max_after_split ? old_page_num : new_page_num;
+
+  internal_node_insert(table, destination_page_num, child_page_num);
+  *node_parent(child) = destination_page_num;
```

Finally, we update the old node's key in its parent, and insert the sibling node and update the sibling node's parent pointer if necessary.

```diff
+  update_internal_node_key(parent, old_max, get_node_max_key(table->pager, old_node));
+
+  if (!splitting_root) {
+    internal_node_insert(table,*node_parent(old_node),new_page_num);
+    *node_parent(new_node) = *node_parent(old_node);
+  }
```

One important change required to support this new logic is in our `create_new_root` function. Before, we were only taking into account situations where the new root's children would be leaf nodes. If the new root's children are instead internal nodes, we need to do two things:
 1. Correctly initialize the root's new children to be internal nodes
 2. In addition to the call to memcpy, we need to insert each of the root's keys into its new left child and update the parent pointer of each of those children

```diff
@@ -661,22 +680,40 @@ void create_new_root(Table* table, uint32_t right_child_page_num) {
   uint32_t left_child_page_num = get_unused_page_num(table->pager);
   void* left_child = get_page(table->pager, left_child_page_num);
 
+  if (get_node_type(root) == NODE_INTERNAL) {
+    initialize_internal_node(right_child);
+    initialize_internal_node(left_child);
+  }
+
   /* Left child has data copied from old root */
   memcpy(left_child, root, PAGE_SIZE);
   set_node_root(left_child, false);
 
+  if (get_node_type(left_child) == NODE_INTERNAL) {
+    void* child;
+    for (int i = 0; i < *internal_node_num_keys(left_child); i++) {
+      child = get_page(table->pager, *internal_node_child(left_child,i));
+      *node_parent(child) = left_child_page_num;
+    }
+    child = get_page(table->pager, *internal_node_right_child(left_child));
+    *node_parent(child) = left_child_page_num;
+  }
+
   /* Root node is a new internal node with one key and two children */
   initialize_internal_node(root);
   set_node_root(root, true);
   *internal_node_num_keys(root) = 1;
   *internal_node_child(root, 0) = left_child_page_num;
-  uint32_t left_child_max_key = get_node_max_key(left_child);
+  uint32_t left_child_max_key = get_node_max_key(table->pager, left_child);
   *internal_node_key(root, 0) = left_child_max_key;
   *internal_node_right_child(root) = right_child_page_num;
   *node_parent(left_child) = table->root_page_num;
   *node_parent(right_child) = table->root_page_num;
 }
```

Another important change has been made to `get_node_max_key`, as mentioned at the beginning of this article. Since an internal node's key represents the maximum of the tree pointed to by the child to its left, and that child can be a tree of arbitrary depth, we need to walk down the right children of that tree until we get to a leaf node, and then take the maximum key of that leaf node.

```diff
+uint32_t get_node_max_key(Pager* pager, void* node) {
+  if (get_node_type(node) == NODE_LEAF) {
+    return *leaf_node_key(node, *leaf_node_num_cells(node) - 1);
+  }
+  void* right_child = get_page(pager,*internal_node_right_child(node));
+  return get_node_max_key(pager, right_child);
+}
```

We have written a single test to demonstrate that our `print_tree` function still works after the introduction of internal node splitting. 

```diff
+  it 'allows printing out the structure of a 7-leaf-node btree' do
+    script = [
+      "insert 58 user58 person58@example.com",
+      "insert 56 user56 person56@example.com",
+      "insert 8 user8 person8@example.com",
+      "insert 54 user54 person54@example.com",
+      "insert 77 user77 person77@example.com",
+      "insert 7 user7 person7@example.com",
+      "insert 25 user25 person25@example.com",
+      "insert 71 user71 person71@example.com",
+      "insert 13 user13 person13@example.com",
+      "insert 22 user22 person22@example.com",
+      "insert 53 user53 person53@example.com",
+      "insert 51 user51 person51@example.com",
+      "insert 59 user59 person59@example.com",
+      "insert 32 user32 person32@example.com",
+      "insert 36 user36 person36@example.com",
+      "insert 79 user79 person79@example.com",
+      "insert 10 user10 person10@example.com",
+      "insert 33 user33 person33@example.com",
+      "insert 20 user20 person20@example.com",
+      "insert 4 user4 person4@example.com",
+      "insert 35 user35 person35@example.com",
+      "insert 76 user76 person76@example.com",
+      "insert 49 user49 person49@example.com",
+      "insert 24 user24 person24@example.com",
+      "insert 70 user70 person70@example.com",
+      "insert 48 user48 person48@example.com",
+      "insert 39 user39 person39@example.com",
+      "insert 15 user15 person15@example.com",
+      "insert 47 user47 person47@example.com",
+      "insert 30 user30 person30@example.com",
+      "insert 86 user86 person86@example.com",
+      "insert 31 user31 person31@example.com",
+      "insert 68 user68 person68@example.com",
+      "insert 37 user37 person37@example.com",
+      "insert 66 user66 person66@example.com",
+      "insert 63 user63 person63@example.com",
+      "insert 40 user40 person40@example.com",
+      "insert 78 user78 person78@example.com",
+      "insert 19 user19 person19@example.com",
+      "insert 46 user46 person46@example.com",
+      "insert 14 user14 person14@example.com",
+      "insert 81 user81 person81@example.com",
+      "insert 72 user72 person72@example.com",
+      "insert 6 user6 person6@example.com",
+      "insert 50 user50 person50@example.com",
+      "insert 85 user85 person85@example.com",
+      "insert 67 user67 person67@example.com",
+      "insert 2 user2 person2@example.com",
+      "insert 55 user55 person55@example.com",
+      "insert 69 user69 person69@example.com",
+      "insert 5 user5 person5@example.com",
+      "insert 65 user65 person65@example.com",
+      "insert 52 user52 person52@example.com",
+      "insert 1 user1 person1@example.com",
+      "insert 29 user29 person29@example.com",
+      "insert 9 user9 person9@example.com",
+      "insert 43 user43 person43@example.com",
+      "insert 75 user75 person75@example.com",
+      "insert 21 user21 person21@example.com",
+      "insert 82 user82 person82@example.com",
+      "insert 12 user12 person12@example.com",
+      "insert 18 user18 person18@example.com",
+      "insert 60 user60 person60@example.com",
+      "insert 44 user44 person44@example.com",
+      ".btree",
+      ".exit",
+    ]
+    result = run_script(script)
+
+    expect(result[64...(result.length)]).to match_array([
+      "db > Tree:",
+      "- internal (size 1)",
+      "  - internal (size 2)",
+      "    - leaf (size 7)",
+      "      - 1",
+      "      - 2",
+      "      - 4",
+      "      - 5",
+      "      - 6",
+      "      - 7",
+      "      - 8",
+      "    - key 8",
+      "    - leaf (size 11)",
+      "      - 9",
+      "      - 10",
+      "      - 12",
+      "      - 13",
+      "      - 14",
+      "      - 15",
+      "      - 18",
+      "      - 19",
+      "      - 20",
+      "      - 21",
+      "      - 22",
+      "    - key 22",
+      "    - leaf (size 8)",
+      "      - 24",
+      "      - 25",
+      "      - 29",
+      "      - 30",
+      "      - 31",
+      "      - 32",
+      "      - 33",
+      "      - 35",
+      "  - key 35",
+      "  - internal (size 3)",
+      "    - leaf (size 12)",
+      "      - 36",
+      "      - 37",
+      "      - 39",
+      "      - 40",
+      "      - 43",
+      "      - 44",
+      "      - 46",
+      "      - 47",
+      "      - 48",
+      "      - 49",
+      "      - 50",
+      "      - 51",
+      "    - key 51",
+      "    - leaf (size 11)",
+      "      - 52",
+      "      - 53",
+      "      - 54",
+      "      - 55",
+      "      - 56",
+      "      - 58",
+      "      - 59",
+      "      - 60",
+      "      - 63",
+      "      - 65",
+      "      - 66",
+      "    - key 66",
+      "    - leaf (size 7)",
+      "      - 67",
+      "      - 68",
+      "      - 69",
+      "      - 70",
+      "      - 71",
+      "      - 72",
+      "      - 75",
+      "    - key 75",
+      "    - leaf (size 8)",
+      "      - 76",
+      "      - 77",
+      "      - 78",
+      "      - 79",
+      "      - 81",
+      "      - 82",
+      "      - 85",
+      "      - 86",
+      "db > ",
+    ])
+  end
```
