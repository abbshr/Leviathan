net = require 'net'
cbor = require 'cbor'
logger = require('./util/logger')()

class Feed
  constructor: (cfg) ->
    {@sock} = cfg
    @server = new net.Server()
    @clients = new Set()
    
  init: ->
    @server
      .on 'connection', @onConnection
      .on 'error', @onError

  push: (feeds) ->
    raw_pack = cbor.encode feeds
    @clients.forEach (client) ->
      client.write raw_pack
    
  onConnection: (socket) =>
    logger.info "[feed server]", "add a subscribe:", socket.remoteAddress, socket.remotePort
    # @createPushStream source, socket
    @clients.add socket
    socket
      # .on 'end', disconnect
      .on 'close', @clients.delete socket
      .on 'error', (err) -> logger.error err
  
  # onClientDisconnect: (socket) ->
  #   => 
    
  onError: (err) =>
    logger.error "[feed server]", err

  open: (callback = ->) ->
    @init()
    @server.listen @sock, callback

  close: (callback = ->) ->
    @clients.clear()
    @server.close callback
    
module.exports = Feed