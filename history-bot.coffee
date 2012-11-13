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
  .demand('server').alias('server', 's').describe('server', 'Server')
  .demand('channel').alias('channel', 'c').describe('channel', 'Channel')
  .demand('botname').alias('botname', 'b').describe('botname', 'Bot Name')
  .alias('user', 'u').describe('user', 'Username for server')
  .alias('password', 'p').describe('password', 'Password for server')
  .boolean('ssl').describe('ssl', 'Use SSL').default('ssl', false)
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
usersLastSaw = {}


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
  usersLastSaw[who] = msgCount


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

  if usersLastSaw[who]?
    console.log "#{who} left #{countMissed(who)} messages ago"

  # auto-catchup, if something new or unknown user.
  catchup who


bot.on 'end', ()->
  console.log "Connection ended"
  # @todo try to reconnect?

bot.on 'close', ()->
  console.log "Connection closed"


countMissed = (who)->
  # differentiate 0 (nothing new) from false (don't know the user)
  if usersLastSaw[who]? then return msgCount - usersLastSaw[who]
  return false

catchup = (who, lastN = 0)->
  # actual # of missed lines. may be > when initially mentioned on re-join.
  if lastN is 0 then lastN = countMissed(who)

  # countMissed returned 0, means the user is known but hasn't missed anything.
  if lastN is 0
    console.log "Nothing new to send #{who}"
    return

  # user isn't recognized, send a bunch
  if lastN is false then lastN = 100

  # don't try to send more than we have
  lastN = Math.min lastN, Object.keys(msgs).length

  console.log "Sending #{who} the last #{lastN} messages"

  # private
  bot.say who, "Catchup on the last #{lastN} messages:"
  for n in [(msgCount-lastN+1)..msgCount]
    if msgs[n]? then bot.say who, msgs[n]


bot.connect()