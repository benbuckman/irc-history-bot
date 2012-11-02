# for testing,
# fill up the room w/noise that we can read with the bot

irc = require 'irc'

channel = '#test-history-bot'
botName = 'noisemaker'

client = new irc.Client 'tanqueray.docusignhq.com', botName,
  channels: [ channel ]
  autoConnect: false  #?

client.addListener 'error', (error) ->
  if error.command != 'err_nosuchnick'
    console.log 'error:', error

client.addListener 'registered', (m) ->
  console.log 'joined chat room'
  client.say channel, 'hello from ' + botName

  # tmp, fill up the log
  setInterval ()->
    client.say channel, "Hello at " + Date()
  , 2000

client.connect()