###
History bot for Martini IRC
- remember when a user logs out
- then when they re-join, invite them to 'catchup'
- user can also 'catchup N' an arbitrary # of lines
- saves max-sized buffer to memory
###

irc = require 'irc'
require 'sugar'  # for dates

# @todo make these parameters?
channel = '#Martini'
botName = 'BigBrother'

client = new irc.Client 'tanqueray.docusignhq.com', botName,
  channels: [ channel ]
  autoConnect: false  #?

client.addListener 'error', (error) ->
  unless error.command is 'err_nosuchnick' then console.log 'error:', error

client.addListener 'registered', (m) ->
  console.log "Joined #{channel}"
  client.say channel, "Big Brother is watching. When you leave this channel and return, " +
    "you can 'catchup' on what you missed, or at any time, 'catchup N' # of lines."

# store messages as hash w/ n:msg
msgs = {}

# current range of msgs
msgCount = 0
msgMin = 1

keepOnly = 1000

# msgCount at which people leave
usersLeftAt = {}


# someone else speaks
client.addListener 'message' + channel, (who, message)->
  # handle 'catchup' requests
  if matches = message.match /^catchup( [0-9]*)?$/
    catchup who, (matches[1] ? 0)
    return

  # everything else
  d = Date.create()
  msgs[++msgCount] = d.format('{m}/{d}/{yy}') + ' ' + d.format('{12hr}:{mm}{tt}') + " #{who}: #{message}"

  # cleanup
  if msgCount - msgMin >= keepOnly
    for n in [msgMin..(msgCount-keepOnly)]
      delete msgs[n]
      msgMin = (n + 1) if n >= msgMin

# someone leaves
client.addListener 'part' + channel, (who, reason)->
  console.log "#{who} left at msg ##{msgCount}"
  usersLeftAt[who] = msgCount

# (don't need to handle kicks)
# client.addListener 'kick' + channel, (channel, who, byWho, reason)->

# someone joins
client.addListener 'join' + channel, (who, message) ->
  console.log "#{who} joined at msg ##{msgCount}"
  if usersLeftAt[who]?
    client.say channel, "Welcome back #{who}. You left us #{countMissed(who)} messages ago. " +
      "To catchup, say 'catchup' or 'catchup [# of msgs]'"
  else
    client.say channel, "Welcome #{who}. I don't recognize you. Say 'catchup N' to see the last N messages."

countMissed = (who)->
  if usersLeftAt[who]? then return msgCount - usersLeftAt[who]
  return 0

catchup = (who, lastN = 0)->
  # actual # of missed lines. may be > when initially mentioned on re-join.
  if lastN is 0 then lastN = countMissed(who)

  if lastN is 0
    client.say channel, "#{who} there's nothing for you to catch up on... please specify a # of lines."
    return

  console.log "Sending #{who} the last #{lastN} messages"

  # private
  client.say who, "Catchup on the last #{lastN} messages:"
  for n in [(msgCount-lastN+1)..msgCount]
    if msgs[n]? then client.say who, msgs[n]


client.connect()