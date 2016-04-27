# Synchronize Agent

net = require 'net'
{PassThrough} = require 'stream'
{log} = require 'util'
cbor = require 'cbor'
level = require 'level'
Ring = require 'node-parted'
Hive = require 'hive-fs'
Gossip = require 'leviathan-gossip'
config = require '../etc/Leviathan'

hive = new Hive config.hive_fs
ring = new Ring config.hash_ring
gossip = new Gossip config.gossip
lldb = level config.leveldb.db_path, valueEncoding: 'json'

bootstrap = (done) ->
  # 读取leveldb中的数据到进程内存
  log "[agent booting] - reading data to Hive-fs..."
  lldb.createReadStream()
    .on 'data', retrieveExistedData
    .on 'end', done
  
retrieveExistedData = ({key, value}) ->
  # 写入gossip状态存储
  gossip.set key, value
  value.idx = key
  # 写入共享内存
  hive.write value, (err) ->
    if err?
      console.error err
    else
      console.info "update:", key

onBooted = ->
  log "[agent booting] - hive initializing finished"
  startInternalServer()
  gossip
  .on 'peers_discover', (new_peers) ->
    for peer in new_peers
      log "[new peer] - found node# #{peer}"
      ring.addNode peer
  .on 'peers_recover', (peers) ->
    ring.addNode peer for peer in peers
  .on 'peers_suspend', (peers) ->
    ring.removeNode peer for peer in peers
  .on 'updates', (deltas) ->
    for [r, k, v, n] in deltas
      log "[delta] - get update from peer #{r}: (key: #{k}, value: #{v}) to version #{n}"      
      lldb.put k, v, (err) ->
        if err?
          log err
        else
          log "[persistent] - delta has been updated to persistent storage"
      
      n.idx = k
      hive.write n, (err) ->
        if err?
          log err
        else
          log "[shared memory] - delta has been updated to Hive-fs"
  
  gossip.run ->
    log "[agent running] - agent start successfully"
    log "[agent running] - init gossip"

serve = (socket) ->
  rawReqStream = new PassThrough()
  ds = new cbor.Decoder()
  es = new cbor.Encoder()
  es.pipe socket
    .pipe passThrough

  socket.pipe ds
    .once 'data', (req_pack) ->
      switch req_pack.cmd
        when "add_service"
          {serviceName, plugins, upstreams} = req_pack
          log "[add service] - #{serviceName} => #{upstream}"
          peer_info = ring.search serviceName
          if peer_info is config.localhost
            # 直接写入
            entry = {plugins, upstream}
            gossip.set serviceName, entry
            lldb.put serviceName, entry
            entry.idx = serviceName
            entry.ts = Date.now()
            hive.write entry, (err) ->
              console.error err if err?

            es.end msg: "accept request"
          else
            # 转发请求到目标peer
            forward peer_info, {downStream: socket, rawReqStream}
        when "config_plugin"
          {serviceName, pluginName, cfg} = req_pack
          key = "#{serviceName}##{pluginName}"
          peer_info = ring.search key
          if peer_info is config.localhost
            # 直接写入
            gossip.set key, cfg
            lldb.put key, cfg
            cfg.idx = key
            cfg.ts = Date.now()
            hive.write cfg, (err) ->
              console.error err if err?

            es.end msg: "accept request"
          else
            # 转发请求到目标peer
            forward peer_info, {downStream: socket, rawReqStream}
        # when "query_service"
        # when "query_plugin"
        # when "delete_service"
        # when "uninstall_plugin"
        else 
          es.end err: "Rejected: unknown packet"
  
startInternalServer = ->
  server = net.createServer serve
  server.listen config.internal_server.sock, ->
    log "[agent booting] - internal server started"
  
forward = (peer_info, {rawReqStream, downStream}, callback = ->) ->
  [addr, port] = peer_info.split ':'
  socket = net.connect peer_info, ->
    rawReqStream.pipe socket
      .pipe downStream
      .on 'end', callback
  
bootstrap onBooted

process.on "SIGTERM", ->
  hive.close()
  lldb.close()
