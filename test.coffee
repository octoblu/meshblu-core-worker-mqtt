#http://blog.airasoul.io/the-internet-of-things-with-rabbitmq-node-js-mqtt-and-amqp/

amqp = require 'amqp'
url = 'amqp://meshblu:some-random-development-password@octoblu.dev:5672/mqtt'
connection = amqp.createConnection({ url: url }, defaultExchangeName: 'amq.topic')
connection.on 'ready', ->
  console.log 'ready'
  connection.queue 'meshblu/queue', {
    durable: true
    autoDelete: false
  }, (q) ->
    console.log 'queue connected'
    q.bind 'meshblu.whoami'
    q.subscribe {
      ack: true
      prefetchCount: 1
    }, (message, headers, deliveryInfo, messageObject) ->
      console.log 'received message', message.data.toString()
      msg = JSON.parse message.data
      console.log deliveryInfo.consumerTag
      replyTo = 'mqtt-subscription-'+msg.replyTo+'qos1'
      console.log replyTo
      connection.publish(replyTo, {
        topic: deliveryInfo.routingKey
        callbackId: msg.callbackId
        data: {'hello':'world'}
      })
      q.shift()
