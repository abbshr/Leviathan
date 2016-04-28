Leviathan
===

Archangel核心系统之一.

Leviathan(利维坦)是一个分布式数据存储服务器, 也是一个基于内存和文件系统的存储仓库.
~~运行时会将数据加载入进程空间内存以及外部的共享内存区(一般是/run/shm或/dev/shm)~~
持久化引擎暂时用LevelDB, hive-fs改进中.

### 架构概要

Leviathan的基石是Gossip算法, 集群以它维护数据最终一致性的.
Gossip的节点选择策略借鉴了Cassandra, 以防出现集群岛隔离情景.
数据的分区策略依据一致性哈希算法, 每个节点的ip:port作为参数计算Hash(ip:port)并散列到环上.
本地持久化引擎使用了具备随机写优势的LevelDB.
节点的故障探测策略采用了PHI累计故障探测算法, 借鉴了Cassandra对PHI值计算方法的修改.
~~数据更新会实时写入tmpfs文件系统(共享内存区), 允许其他异构系统通过hive-fs获取更新~~. 当前异构系统可以通过Feed Stream实时获取更新.
采用了CBOR规范作为报文格式化协议.

### 内部组件


+ leviathan-gossip: Leviathan的gossip库, 内部实现了PHI累计故障探测模块
+ ~~hive-fs: 构建在文件系统之上的块存储系统~~
+ parted: Leviathan的一致性哈希实现
+ leveldb: 持久化引擎
+ cbor: 上层通信协议

### BootStrap

```bash
bin/Leviathan [configFile path]
```

### Configuration

示例: `etc/Leviathan.yaml`


### Issues && TODO

尚未支持键的删除,
代码结构待调整,
测试待完善
替换存储引擎:Hive-fs替换leveldb, hive-fs改进中,
命令行参数支持不好