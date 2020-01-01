---
title: 데이터베이스는 어떻게 작동하는가?
---

- 데이터가 어떠한 형식으로 저장되는가? (메모리와 디스크에)
- 언제 메모리에서 디스크로 옮겨지는가?
- 왜 테이블마다 하나의 주키만을 가질 수 있는가?
- 어떻게 트랜잭션 롤백이 수행되는가?
- 인덱스는 어떻게 구성되는가?
- 전체 테이블 탐색(full table scan) 작업은 언제, 어떻게 수행되는가?
- 준비된 문장(prepared statement)은 어떠한 형식으로 저장되는가?

즉, 데이터베이스는 어떻게 **작동** 하는가?

필자는 데이터베이스를 이해하기 위해, C언어로 sqlite를 바닥부터 본뜨는 작업을 진행하며, 모든 진행 과정을 문서로 기록합니다.

# 목차
{% for part in site.parts %}- [{{part.title}}]({{site.baseurl}}{{part.url}})
{% endfor %}

> "내가 만들어낼 수 없다면, 이해하지 못한 것이다." -- [리처드 파인만](https://en.m.wikiquote.org/wiki/Richard_Feynman)

{% include image.html url="assets/images/arch2.gif" description="sqlite 구조 (https://www.sqlite.org/arch.html)" %}