# setup yaml complier
{safeLoad} = require 'js-yaml'
{readFileSync} = fs
require.extensions['.yaml'] = (module, filename) ->
  try
    module.exports = safeLoad readFileSync filename
  catch err
    err.message = "#{filename}: #{err.message}"
    throw err
