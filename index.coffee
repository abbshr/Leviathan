net = require 'net'
{log} = require 'util'
{fork} = require 'child_process'

spawnAgent = ->
  onExit = (code, signal) ->
    log "Leviathan agent exit with code [#{code}]. Due to signal [#{signal}]"
    log "Respawning..."
    spawnAgent()
  onError = (err) -> log err
  onDisconnect = -> log "Leviathan agent offline"
  
  agent = fork "../lib/agent/sync.coffee"
  agent
    .on 'exit', onExit
    .on 'error', onError
    .on 'disconnect', onDisconnect

SIG = ["SIGTERM", "SIGKILL", "SIGHUP", "SIGINT"]

process.on sig, -> agent.kill "SIGTERM" for sig in signal
