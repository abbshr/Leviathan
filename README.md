Leviathan
===

Archangel核心系统之一.

Leviathan(利维坦)是一个分布式数据存储服务器, 也是一个基于内存和文件系统的存储仓库.
运行时会将数据加载入进程空间内存以及外部的共享内存区(一般是/run/shm或/dev/shm)
持久化引擎使用hive-fs.

### 架构概要

Leviathan的基石是Gossip算法, 集群以它维护数据最终一致性的.
Gossip的节点选择策略借鉴了Cassandra, 以防出现集群岛隔离情景.
数据的分区策略依据一致性哈希算法, 每个节点的ip:port作为参数计算Hash(ip:port)并散列到环上.
本地持久化引擎使用了具备随机写优势的LevelDB.
节点的故障探测策略采用了PHI累计故障探测算法, 借鉴了Cassandra对PHI值计算方法的修改.
当前异构系统可以通过Feed Stream实时获取更新.
采用了CBOR规范作为报文格式化协议.

### 内部组件


+ leviathan-gossip: Leviathan的gossip库, 内部实现了PHI累计故障探测模块
+ hive-fs: 持久化引擎
+ parted: Leviathan的一致性哈希实现
+ cbor: 上层通信协议

### BootStrap

deploy:
```bash
npm run build
```

run:
```bash
bin/Leviathan [configFile path]
```

### Configuration

示例: `etc/Leviathan.yaml`


### Issues && TODO

尚未支持键的删除,
代码结构待调整,
测试待完善
命令行参数支持不好

### 增删节点情况下的系统可用性

Leviathan采用"本地读&异地写"策略, 通过一致性哈希查找一个写操作的节点地址并将请求转发/直接写入本地.
而对于读操作, Leviathan是通过本地缓存响应请求. 在Leviathan同步过程中, 经过近似logN的时间整个集群达到状态一致,
因此无论增删节点, 本地读取满足读操作要求且不受影响.
