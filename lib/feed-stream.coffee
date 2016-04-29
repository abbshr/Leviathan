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
    logger.info "[feed server]", "add a local subscriber"
    # @createPushStream source, socket
    @clients.add socket
    socket
      # .on 'end', disconnect
      .on 'close', =>
        logger.info "[feed server]", "a local client unsubscribe the feeds" 
        @clients.delete socket
      .on 'error', (err) => logger.error "[feed server]", err.message
  
  # onClientDisconnect: (socket) ->
  #   => 
    
  onError: (err) =>
    logger.error "[feed server]", err.message

  open: (callback = ->) ->
    @init()
    @server.listen @sock, callback

  close: (callback = ->) ->
    @server.close callback
    @clients.forEach (client) ->
      client.end()
    @clients.clear()

module.exports = Feed