#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Define InputBuffer as a small wrapper around the 
// state we need to store to interact with getline()
typedef struct {
    char* buffer;
    // typedef unsigned int size_t;为无符号整型
    size_t buffer_length;
    // ssize_t是C语言头文件stddef.h中定义的类型。
    // ssize_t是有符号整型，在32位机器上等同与int，在64位机器上等同与long int.
    ssize_t input_length;
} InputBuffer;

// Initialize a InputBuffer pointer
InputBuffer* new_input_buffer(){
    // 指针也就是内存地址，指针变量是用来存放内存地址的变量。
    // malloc() 函数返回一个指针 ，指向已分配大小的内存。casted as InputBuffer*
    InputBuffer* input_buffer = (InputBuffer*)malloc(sizeof(InputBuffer));
    // 为了使用指向该结构的指针访问结构的成员，您必须使用 -> 运算符
    input_buffer->buffer = NULL;
    input_buffer->buffer_length = 0;
    input_buffer->input_length = 0;
    return input_buffer;
}

// print_prompt() prints a prompt to the user. 
// We do this before reading each line of input.
void print_prompt() { printf("db > "); }

// To read a line of input, use getline():

// lineptr : a pointer to the variable we use to point to the buffer 
// containing the read line. 
// If it set to NULL it is mallocatted by getline and 
// should thus be freed by the user, even if the command fails.

// n : a pointer to the variable we use to save the size of allocated buffer.

// stream : the input stream to read from. We’ll be reading from standard input.

// return value : the number of bytes read, 
// which may be less than the size of the buffer.

// We tell getline to store the read line in input_buffer->buffer 
// and the size of the allocated buffer in input_buffer->buffer_length. 
// We store the return value in input_buffer->input_length.
// buffer starts as null, so getline allocates enough memory to 
// hold the line of input and makes buffer point to it.
// lineptr：指向存放该行字符的指针，如果是NULL，则有系统帮助malloc，请在使用完成后free释放。
// stream：文件描述符
ssize_t getline(char **lineptr, size_t *n, FILE *stream);
// 多级指针，指向指针的指针, 例如，int ** 存 int * 的地址,  
// 二级指针存一级指针的地址，那么可以说二级指针指向一级指针

void read_input(InputBuffer* input_buffer){
    // stdin是标准输入，一般指键盘输入到缓冲区里的东西，采用perl语言实现。
    ssize_t bytes_read = getline(&(input_buffer->buffer), &(input_buffer->buffer_length), stdin);
    if (bytes_read <= 0) {
        printf("Error reading input\n");
        exit(EXIT_FAILURE);
    }
    // Ignore trailing newline
    input_buffer->input_length = bytes_read-1;
    // 初始化由返回char数据的指针所组织成的数组，长度为bytes_read-1
    input_buffer->buffer[bytes_read-1] = 0;
}

// Now it is proper to define a function that frees the memory 
// allocated for an instance of InputBuffer * and 
// the buffer element of the respective structure 
// (getline allocates memory for input_buffer->buffer in read_input).
void close_input_buffer(InputBuffer* input_buffer){
    free(input_buffer->buffer);
    free(input_buffer);
}

// argc 为参数个数，argv是字符串数组, 第一个存放的是可执行程序的文件名字，然后依次存放传入的参数
int main(int argc, char* argv[])
{
    // Sqlite starts a read-execute-print-loop when you start it from the command line
    // to do that, the main function will have
    // an infinite loop that prints the prompt, gets a line of input, 
    // then processes that line of input:
    InputBuffer* input_buffer = new_input_buffer();
    while (true) {
        print_prompt();
        read_input(input_buffer);
        // Finally we parse and execute the command.
        // There is only one recognized command right now:
        // .exit, which terminates the program. Otherwise, we print an error msg and continue the loop.
        if (strcmp(input_buffer->buffer, ".exit") == 0){
            close_input_buffer(input_buffer);
            exit(EXIT_SUCCESS);
        } else {
            printf("Unrecognized command '%s'.\n", input_buffer->buffer);
            
        }
    }
    
}