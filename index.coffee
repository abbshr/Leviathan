# setup extend YAML `require` parser
require './lib/util/yaml-extend'

{fork} = require 'child_process'
logger = require('./lib/util/logger')()

class Master

  SIG: ["SIGTERM", "SIGINT", "SIGABRT", "SIGHUP"]
  constructor: () ->
    @exec_path = "./lib/agent/sync.coffee"
    @_closing = no
    @agent = null
    
  fork: ->
    logger.info "[master]", "process start"
    master = new Master()
    master.init()
    master.spawnAgent()
    
  init: ->
    for sig in @SIG
      logger.info "[master]", "registry signal event:", sig
      process.on sig, @signalHandle sig
          
  signalHandle: (signal) =>
    =>
      logger.warn "[master]", "got signal:", signal
      @_closing = yes
      @agent?.kill "SIGTERM"
  
  spawnAgent: ->
    logger.info "[master]", "spawning agent process"
    @agent = fork @exec_path, process.argv[2..]
    @initAgent() 

  initAgent: ->
    @agent?.on 'exit', @onAgentExit
      .on 'error', @onAgentError
      .on 'disconnect', @onAgentDisconnect
      
  uninitAgent: ->
    @agent?.removeListener 'exit', @onAgentExit
      .removeListener 'error', @onAgentError
      .removeListener 'disconnect', @onAgentDisconnect
  
  onAgentExit: (code, signal) =>
    logger.warn "[master] agent exit with code [#{code}], due to signal [#{signal}]" 
    @uninitAgent()
    if @_closing
      logger.warn "[master]", "process exit"
      process.exit 0
    else
      logger.info "respawning..."
      @spawnAgent()
  
  onAgentError: (err) => logger.error err
  
  onAgentDisconnect: => logger.warn '[master]', 'agent disconnect'

module.exports = Master