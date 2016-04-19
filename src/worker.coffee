{Client}              = require 'amqp10'
Promise               = require 'bluebird'
debug                 = require('debug')('meshblu-core-worker-amqp:worker')
RedisPooledJobManager = require 'meshblu-core-redis-pooled-job-manager'

class Worker
  constructor: (options)->
    {@jobTimeoutSeconds, @jobLogQueue, @jobLogRedisUri, @jobLogSampleRate} = options
    {@amqpUri, @maxConnections, @redisUri, @namespace} = options

  connect: (callback) =>
    options =
      reconnect:
        forever: false
        retries: 0

    @client = new Client options
    @client.connect @amqpUri
      .then =>
        @client.once 'connection:closed', =>
          throw new Error 'connection to amqp server lost'
        Promise.all [
          @client.createSender()
          @client.createReceiver('meshblu.request')
        ]
      .spread (@sender, @receiver) =>
        callback()
        return true # promises are dumb
      .catch (error) =>
        callback error
      .error (error) =>
        callback error

  run: (callback) =>
    @connect (error) =>
      return callback error if error?

      @jobManager = new RedisPooledJobManager {
        jobLogIndexPrefix: 'metric:meshblu-core-worker-amqp'
        jobLogType: 'meshblu-core-worker-amqp:request'
        @jobTimeoutSeconds
        @jobLogQueue
        @jobLogRedisUri
        @jobLogSampleRate
        @maxConnections
        @redisUri
        @namespace
      }

      @receiver.on 'message', (message) =>
        debug 'message received:', message
        job = @_amqpToJobManager message
        debug 'job:', job

        @jobManager.do 'request', 'response', job, (error, response) =>
          debug 'response received:', response

          options =
            properties:
              correlationId: message.properties.correlationId
              subject: message.properties.replyTo
            applicationProperties:
              code: response.code || 0

          debug 'sender options', options
          @sender.send response.rawData, options

  stop: (callback) =>
    @client.disconnect()
      .then callback
      .catch callback

  _amqpToJobManager: (message) =>
    job =
      metadata: message.applicationProperties
      rawData: message.body

module.exports = Worker
