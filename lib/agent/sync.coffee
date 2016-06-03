# Synchronize Agent
# setup extend YAML `require` parser
require '../util/yaml-extend'

net = require 'net'
{PassThrough} = require 'stream'
cbor = require 'cbor'
level = require 'level'
{Hive} = require 'hive-fs'
Ring = require 'node-parted'
Gossip = require 'leviathan-gossip'
FeedStream = require '../feed-stream'
logger = require('../util/logger')()

config_path = process.argv[2] ? '../../etc/Leviathan'
config = require config_path

ring = new Ring replica: config.hash_ring.replica, nodes: [config.localhost]
gossip = new Gossip config.gossip
# lldb = level config.leveldb.db_path, valueEncoding: 'json'
hive = new Hive config.hive
internal_server = new net.Server
feed_stream = new FeedStream config.feed_stream    

bootstrap = (done = ->) ->
  process.on 'SIGINT', ->

  process.on "SIGTERM", ->
    logger.warn "[agent]", "got signal: SIGTERM"
    internal_server.close ->
      logger.warn "[agent]", "internal server closed"
      # lldb.close (err) ->
      hive.close (err) ->
        logger.warn "[agent]", "hivefs closed"
        feed_stream.close ->
          logger.warn "[agent]", "feed stream server closed"
          logger.warn "[agent]", "process exit"
          process.exit 0
  
  logger.info "[agent]", "process start"
  feed_stream.open ->
    logger.info "[agent]", "feed stream server start"
  # 读取hive-fs中的数据到进程内存
  logger.info "[agent]", "retrieving data from hive-fs..."
  # lldb.createReadStream()
  hive.match()
    .on 'data', retrieveExistedData
    .on 'end', done
  
retrieveExistedData = (key, [value, version]) ->
  logger.info "[agent]", "get data from hive-fs: ", "<#{key}: #{value}>"
  # 写入gossip状态存储
  gossip.set key, value
  feed_stream.push [[key, value, version]]

onBooted = ->
  gossip
  .on 'peers_discover', (new_peers) ->
    for peer in new_peers
      logger.info "[agent]", "found new peers:", peer
      ring.addNode peer
  .on 'peers_recover', (peers) ->
    for peer in peers
      ring.addNode peer
      logger.info "[agent]", "peer online:", peer
  .on 'peers_suspend', (peers) ->
    for peer in peers
      ring.removeNode peer
      logger.warn "[agent]", "peer crashed:", peer
  .on 'updates', (deltas) ->
    feeds = for [r, k, v, n] in deltas
      logger.verbose "[agent]", "get update from peer [#{r}]: (key: #{k}, value:", v, ") to version #{n}"
      # if r is config.localhost
      # lldb.put k, [v, n], (err) ->
      hive.write k, [v, n], (err) ->
        if err?
          logger.error err
        else
          logger.info "[agent]", "delta has been updated to hive-fs"
      [k, v, n]
    feed_stream.push feeds

  gossip.run ->
    logger.info "[agent]", "gossip inited"
    startInternalServer()

serve = (socket) ->
  rawReqStream = new PassThrough()
  ds = new cbor.Decoder()
  es = new cbor.Encoder()
  es.pipe socket
    .pipe rawReqStream

  socket.pipe ds
    .once 'data', (req_pack) ->
      switch req_pack.cmd
        when "add_service"
          {serviceName, plugins = [], upstreams = []} = req_pack
          peer_info = ring.schedule serviceName
          if peer_info is config.localhost
            logger.info "[agent]", "add service: #{serviceName}, upstreams: #{upstreams}"
            # 直接写入
            entry = {plugins, upstreams}
            version = gossip.set serviceName, entry
            feed_stream.push [[serviceName, entry, version]]
            # lldb.put serviceName, [entry, version]
            hive.write serviceName, [entry, version], ->

            es.end msg: "peer <#{config.localhost}> accept request"
          else
            # 转发请求到目标peer
            forward peer_info, {downStream: socket, rawReqStream}
        when "config_plugin"
          {serviceName, pluginName, cfg = {}} = req_pack
          key = "#{serviceName}##{pluginName}"
          peer_info = ring.schedule key
          if peer_info is config.localhost
            logger.info "[agent]", "config plugin: #{pluginName} for service: #{serviceName}"
            # 直接写入
            version = gossip.set key, cfg
            feed_stream.push [[key, cfg, version]]
            # lldb.put key, [cfg, version]
            hive.write key, [cfg, version], ->

            es.end msg: "peer <#{config.localhost}> accept request"
          else
            # 转发请求到目标peer
            forward peer_info, {downStream: socket, rawReqStream}
        when "query_service"
          {serviceName} = req_pack
          logger.info "[agent]", "query service: #{serviceName}"
          # lldb.get serviceName, (err, [entry, ...] = []) ->
          hive.seek serviceName, (err, [entry, ...] = []) ->
            if err?
              es.end err: err.message
            else
              es.end msg: entry
        when "query_plugin"
          {serviceName, pluginName} = req_pack
          logger.info "[agent]", "query plugin: #{serviceName} -> #{pluginName}"
          key = "#{serviceName}##{pluginName}"
          # lldb.get key, (err, [entry, ...] = []) ->
          hive.seek key, (err, [entry, ...] = []) ->
            if err?
              es.end err: err.message
            else
              es.end msg: entry
        # when "delete_service"
        # when "uninstall_plugin"
        else
          es.end err: "Rejected: unknown packet"
  
startInternalServer = (done = ->)->
  internal_server.on 'connection', serve
  if config.internal_server.sock?
    internal_server.listen config.internal_server.sock, ->
      logger.info "[agent]", "internal server started, listen on", config.internal_server.sock
  else
    internal_server.listen config.internal_server.port, ->
      logger.info "[agent]", "internal server started, listen on", config.internal_server.port
  
forward = (peer_info, {rawReqStream, downStream}, callback = ->) ->
  [addr, sock_port] = peer_info.split ':'
  port = config.internal_server.port
  sock = "./run/#{sock_port}.sock"
  
  socket = if config.internal_server.sock?
    net.connect sock
  else
    net.connect port, addr
  
  socket
    .on 'error', (err) ->
      logger.error "[agent]", err.message
    .on "connect", ->
      rawReqStream.pipe socket
        .pipe downStream
        .on 'end', callback
  
bootstrap onBooted