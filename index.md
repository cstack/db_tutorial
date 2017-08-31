# How Does a Database Work?
- What format is data saved in? (in memory and on disk)
- When does it move from memory to disk?
- Why can there only be one primary key per table?
- How does rolling back a transaction work?
- How are indexes formatted?
- When and how does a full table scan happen?
- What format is a prepared statement save in?

In short, how does a database **work**?

I'm building a clone of [sqlite](https://www.sqlite.org/arch.html) from scratch in C in order to understand, and I'm going to document my process as I go.

# Table of Contents
[Part 1 - Introduction and Setting up the REPL](part1.md)

{% include image.html url="assets/images/arch2.gif" description="sqlite architecture (https://www.sqlite.org/arch.html)" %}