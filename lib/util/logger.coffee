{Logger, transports: {Console}} = require 'winston'

opts = 
  colorize: yes
  timestamp: yes
  level: 'silly'
module.exports = ->
  new Logger transports: [new Console opts]