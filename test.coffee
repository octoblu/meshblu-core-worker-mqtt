amqp                  = require 'amqp'
debug                 = require('debug')('meshblu-core-worker-amqp:worker')
RedisPooledJobManager = require 'meshblu-core-redis-pooled-job-manager'

#http://blog.airasoul.io/the-internet-of-things-with-rabbitmq-node-js-mqtt-and-amqp/

url = 'amqp://meshblu:some-random-development-password@octoblu.dev:5672/mqtt'

connection = amqp.createConnection({ url: url }, defaultExchangeName: 'amq.topic')

connection.on 'ready', ->
  console.log 'ready'
  connection.queue 'meshblu.queue', {
    durable: true
    autoDelete: false
  }, attachMeshbluQueue

attachMeshbluQueue = (q) ->
  console.log 'queue connected'
  q.bind 'meshblu.request'
  q.bind 'meshblu.cache-auth'
  q.bind 'meshblu.reply-to'
  q.subscribe {
    ack: true
    prefetchCount: 1
  }, (message, headers, deliveryInfo, messageObject) ->
    console.log 'received message', message.data.toString()
    msg = JSON.parse message.data
    replyTo = msg.jobInfo.replyTo
    console.log {deliveryInfo}
    connection.publish(replyTo, {
      callbackId: msg.jobInfo.callbackId
      data: {'hello':'world'}
    }) if replyTo?
    q.shift()
