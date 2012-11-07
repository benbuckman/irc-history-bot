###
History bot for Martini IRC
- remember when a user logs out
- then when they re-join, invite them to 'catchup'
- user can also 'catchup N' an arbitrary # of lines
- saves max-sized buffer to memory
- ONE CHANNEL AT A TIME - to run multiple channels, run multiple bots
###

irc = require 'irc'
require 'sugar'  # for dates

argv = require('optimist')
  .usage('Usage: $0 [--ssl] -s <server> [-u <user>] [-p <password>] [-b <botName>] -c <channel>')
  .demand(['s','c'])
  .default('c', '#Martini')
  .default('b', 'BigBrother')
  .boolean('ssl').default('ssl', false)
  .argv

server = argv.s
channel = argv.c
try if not channel.match(/^#/) then channel = '#' + channel
botName = argv.b

console.log "Connecting to #{channel} on #{server} as #{botName} " +
  (if argv.ssl then "with SSL" else "without SSL")

bot = new irc.Client server, botName,
  channels: [ channel ]
  autoConnect: false
  secure: argv.ssl
  userName: argv.u
  password: argv.p
  selfSigned: true
  certExpired: true

bot.on 'error', (error) ->
  unless error.command is 'err_nosuchnick' then console.log 'error:', error

bot.on 'registered', (m) ->
  console.log "Joined #{channel}"

# store messages as hash w/ n:msg
msgs = {}

# current range of msgs
msgCount = 0
msgMin = 1

keepOnly = 1000

# msgCount at which people leave
usersLeftAt = {}


# someone else speaks
bot.on 'message' + channel, (who, message)->
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


quitHandler = (who, type = "left")->
  console.log "#{who} #{type} at msg ##{msgCount}"
  usersLeftAt[who] = msgCount

# 3 ways to leave
bot.on 'part' + channel, (who, reason)->
  quitHandler who, 'left'
bot.on 'kick' + channel, (who, byWho, reason)->
  quitHandler who, 'kicked'
bot.on 'quit', (who, reason, channels, message)->
  if channel in channels then quitHandler who, 'quit'


# someone joins
bot.on 'join' + channel, (who, message) ->
  # self? (instead of 'registered' which our new server doesn't like, pre-join)
  if who is botName and msgCount is 0
    bot.say channel, "#{botName} is watching. When you leave this channel and return, " +
      "you can 'catchup' on what you missed, or at any time, 'catchup N' # of lines."
    return

  console.log "#{who} joined at msg ##{msgCount}"

  # [auto-catchup]
  catchup who

  if usersLeftAt[who]?
    console.log "#{who} left #{countMissed(who)} messages ago"
  #   bot.say channel, "Welcome back #{who}. You left us #{countMissed(who)} messages ago. " +
  #     "To catchup, say 'catchup' or 'catchup [# of msgs]'"
  # else if who isnt botName
  #   bot.say channel, "Welcome #{who}. I don't recognize you. Say 'catchup N' to see the last N messages."
  #   catchup who


bot.on 'end', ()->
  console.log "Connection ended"
  # @todo try to reconnect?

bot.on 'close', ()->
  console.log "Connection closed"


countMissed = (who)->
  if usersLeftAt[who]? then return msgCount - usersLeftAt[who]
  return 0

catchup = (who, lastN = 0)->
  # actual # of missed lines. may be > when initially mentioned on re-join.
  if lastN is 0 then lastN = countMissed(who)

  # (user isn't recognized, send a bunch)
  if lastN is 0
    lastN = 100

    # [old]
    # bot.say channel, "#{who} there's nothing for you to catch up on... please specify a # of lines."
    # return

  lastN = Math.min(lastN, msgs.length)

  console.log "Sending #{who} the last #{lastN} messages"

  # private
  bot.say who, "Catchup on the last #{lastN} messages:"
  for n in [(msgCount-lastN+1)..msgCount]
    if msgs[n]? then bot.say who, msgs[n]


bot.connect()