---
title: パート1 - イントロダクションとREPLのセットアップ
date: 2017-08-30
---

web開発者として、[私](https://github.com/cstack)はデータベースを毎日使います。しかしデータベースの中身がブラックボックスのように感じます。いくつか不思議に思っていることがあります。:
- データは(メモリと外部記憶装置などにおいて)どのようにして保存されるのでしょうか?
- いつデータはメモリから外部記憶装置に移されるのでしょうか?
- なぜテーブルごとのキーは一意なのでしょうか?
- トランザクションのローリングバックの仕組みはどのようなものなのでしょうか?
- インデックスのフォーマットの仕組みはどのようなものでしょうか?
- いつ、どんな感じで、テーブルが満タンになったとき何が起きるのでしょうか?
- プリペアドステートメントはどのようなフォーマットで保存されるのでしょうか?

手短に言うと、どのようにしてデータベースは**動くのでしょうか?**

これらの謎を解くために、私はデータベースをフルスクラッチで作っています。MySQLやPostgreSQLといったものよりも軽量で、機能も少ないためsqliteをモデルにしました。なので、データベースをより理解しやすくなったと思っています。実はデータベースは一つのファイルに、保存されているのです!

# Sqlite

[sqliteの仕組み](https://www.sqlite.org/arch.html)がsqliteのサイトにあり, そして私は[SQLite Database System: Design and Implementation](https://play.google.com/store/books/details?id=9Z6IQQnX1JEC)という電子書籍を持っています。

{% include image.html url="assets/images/arch1.gif" description="sqliteの構造(https://www.sqlite.org/zipvfs/doc/trunk/www/howitworks.wiki)" %}

クエリは以下のような手順で、取得や変更したデータを解析しています。**フロントエンド** はこれらの要素から構成されています。:
- 字句解析(tokenizer)
- パーサー(parser)
- コード生成

SQLクエリがフロントエンドに入力された時、出力はsqliteの仮想マシンの中間コードへ変換されます。(データベースを操作するには、コンパイルされたプログラムが必要なのです。)

_バックエンド_ はこれらの要素から成り立っています:
- 仮想マシン
- B木
- ページャー
- OSインターフェース

**仮想マシン**はフロントエンドの段階で生成されたバイトコードを使用します。B木と呼ばれるデータ構造にそれぞれのデータは保存され、多数のテーブルやインデックスを操作します。仮想マシンはバイトコードの実行を切り替えるのに必要です。

**B木**は多くのノードから成り立っています。それらは一つのページに収められています。B木はページャーにディスクに戻す命令を発行し、ディスクからページを取得したり保存します。

**ページャー**はデータを読み書きする命令を出します。ページャーはデータベースを適切なオフセットで読み書きします。ページャーはメモリに最近使用したページのキャッシュを保存し、ディスクにページを書き戻す時に使用されます。

**os interface**はsqliteがコンパイルされたOSによって異なります。このチュートリアルは、様々なプラットフォームをサポートします。

[千里の道は一歩から!](https://ja.wiktionary.org/wiki/%E5%8D%83%E9%87%8C%E3%81%AE%E9%81%93%E3%82%82%E4%B8%80%E6%AD%A9%E3%81%8B%E3%82%89)、簡単なところから始めましょう!:REPL

## シンプルなREPLを作ってみよう!

Sqliteはコマンドラインから起動すると、REPLになります。:

```shell
~ sqlite3
SQLite version 3.16.0 2016-11-04 19:09:39
Enter ".help" for usage hints.
Connected to a transient in-memory database.
Use ".open FILENAME" to reopen on a persistent database.
sqlite> create table users (id int, username varchar(255), email varchar(255));
sqlite> .tables
users
sqlite> .exit
~
```

このような処理を行うため、メイン関数は、プロンプトを表示して、入力を読み込み、それを処理する無限ループへ入ります。:

```c
int main(int argc, char* argv[]) {
  InputBuffer* input_buffer = new_input_buffer();
  while (true) {
    print_prompt();
    read_input(input_buffer);

    if (strcmp(input_buffer->buffer, ".exit") == 0) {
      close_input_buffer(input_buffer);
      exit(EXIT_SUCCESS);
    } else {
      printf("Unrecognized command '%s'.\n", input_buffer->buffer);
    }
  }
}
```

`InputBuffer`を[getline()](https://manpages.debian.org/unstable/manpages-ja-dev/getline.3.ja.html)関数で、保存するためのラッパー変数として使用します。(このことについて、後程述べたいと思います。)
```c
typedef struct {
  char* buffer;
  size_t buffer_length;
  ssize_t input_length;
} InputBuffer;

InputBuffer* new_input_buffer() {
  InputBuffer* input_buffer = (InputBuffer*)malloc(sizeof(InputBuffer));
  input_buffer->buffer = NULL;
  input_buffer->buffer_length = 0;
  input_buffer->input_length = 0;

  return input_buffer;
}
```

次に、`print_prompt()`はユーザーにプロンプトを表示する関数です。入力を読み取る前にこれを実行します。

```c
void print_prompt() { printf("db > "); }
```

入力されたものを読み込むため、[getline()](https://manpages.debian.org/unstable/manpages-ja-dev/getline.3.ja.html)関数を使います。:
```c
ssize_t getline(char **lineptr, size_t *n, FILE *stream);
```
`lineptr` : は読み込んだものを保存しているバッファを指し示すポインタ変数です。もし`NULL`が設定されていれば、`getline`によって割り当てられた時、コマンドが失敗したとしても、ユーザーは明示的に解放する必要があります。

`n` : 割り当てられたバッファサイズを保存するポインタ変数です。

`stream` : 入力ストリームから読み込んだ変数を表しています。標準入力から読み込まれます。

`return value` : これの戻り値は読み込んだバイト数を表していて、バッファのサイズより小さいときもあります。

`getline`は読み込んだ行を`input_buffer->buffer`保存し、割り当てられたバッファのサイズを`input_buffer->buffer_length`に保存します。戻り値を`input_buffer->input_length`に保存します。

`buffer`はNULLで始まるため、`getline`は、入力したものを保存するために必要なメモリを割り当てて、`buffer`がそれを指し示します。

```c
void read_input(InputBuffer* input_buffer) {
  ssize_t bytes_read =
      getline(&(input_buffer->buffer), &(input_buffer->buffer_length), stdin);

  if (bytes_read <= 0) {
    printf("Error reading input\n");
    exit(EXIT_FAILURE);
  }

  // 最後の行の改行を無視する
  input_buffer->input_length = bytes_read - 1;
  input_buffer->buffer[bytes_read - 1] = 0;
}
```

ここで、`InputBuffer *`のインスタンス変数と`buffer`の要素のメモリを
解放する関数が必要です。
(`getline`は`read_input`の中の`input_buffer->buffer`へメモリを割り当てます。
)。

```c
void close_input_buffer(InputBuffer* input_buffer) {
    free(input_buffer->buffer);
    free(input_buffer);
}
```

最後に、私たちはパースして、コマンドを実行します。たった一つの今すぐ実行できるコマンドがあります。: `.exit`それはプログラムを終了するというコマンドです。さもなければ、私たちはエラーを出力して、ループを継続します。

```c
if (strcmp(input_buffer->buffer, ".exit") == 0) {
  close_input_buffer(input_buffer);
  exit(EXIT_SUCCESS);
} else {
  printf("Unrecognized command '%s'.\n", input_buffer->buffer);
}
```

試してみましょう!
```shell
~ ./db
db > .tables
'.tables'は認識できません
db > .exit
~
```

さて、動作できるREPLを完成させました!次のパートでは、オリジナルのコマンドライン言語を開発します。さて、今まで作成したプログラムの全体図を示します。:

```c
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  char* buffer;
  size_t buffer_length;
  ssize_t input_length;
} InputBuffer;

InputBuffer* new_input_buffer() {
  InputBuffer* input_buffer = malloc(sizeof(InputBuffer));
  input_buffer->buffer = NULL;
  input_buffer->buffer_length = 0;
  input_buffer->input_length = 0;

  return input_buffer;
}

void print_prompt() { printf("db > "); }

void read_input(InputBuffer* input_buffer) {
  ssize_t bytes_read =
      getline(&(input_buffer->buffer), &(input_buffer->buffer_length), stdin);

  if (bytes_read <= 0) {
    printf("Error reading input\n");
    exit(EXIT_FAILURE);
  }

  // 最後の行の改行を無視する
  input_buffer->input_length = bytes_read - 1;
  input_buffer->buffer[bytes_read - 1] = 0;
}

void close_input_buffer(InputBuffer* input_buffer) {
    free(input_buffer->buffer);
    free(input_buffer);
}

int main(int argc, char* argv[]) {
  InputBuffer* input_buffer = new_input_buffer();
  while (true) {
    print_prompt();
    read_input(input_buffer);

    if (strcmp(input_buffer->buffer, ".exit") == 0) {
      close_input_buffer(input_buffer);
      exit(EXIT_SUCCESS);
    } else {
      printf("Unrecognized command '%s'.\n", input_buffer->buffer);
    }
  }
}
```
