MultiHydrantFactory = require 'meshblu-core-manager-hydrant/multi'
UuidAliasResolver   = require 'meshblu-uuid-alias-resolver'
JobManager          = require 'meshblu-core-redis-pooled-job-manager'
RedisNS             = require '@octoblu/redis-ns'
redis               = require 'ioredis'
debug               = require('debug')('meshblu-core-worker-mqtt:worker')
async               = require 'async'
uuid                = require 'uuid'
amqp                = require 'amqp'
_                   = require 'lodash'

class Worker
  constructor: (options={}, dependencies={})->
    { @jobTimeoutSeconds, @jobLogQueue, @jobLogRedisUri, @jobLogSampleRate, @maxConnections,
      @redisUri, @namespace, @hydrantNamespace, @aliasServerUri } = options
    @redisClient = new RedisNS @namespace, redis.createClient(@redisUri)
    @jobManager = new JobManager {
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

    console.log {@hydrantNamespace, @redisUri}

    # @hydrant.client.once 'ready', =>
    #   debug 'hydrantClient is ready'

    # uuidAliasClient = new RedisNS 'uuid-alias', redis.createClient(@redisUri)
    # uuidAliasResolver = new UuidAliasResolver
    #   cache: uuidAliasClient
    #   aliasServerUri: @aliasServerUri
    debug 'constructed!'

  connect: (callback=->) =>
    debug 'connecting'

    url = 'amqp://meshblu:some-random-development-password@octoblu.dev:5672/mqtt'
    @connection = amqp.createConnection({url}, defaultExchangeName: 'amq.topic')
    @connection.on 'ready', =>
      console.log 'amqp ready'
      @connection.queue 'meshblu.queue', {
        durable: true
        autoDelete: false
      }, (q) =>
        uuidAliasResolver = { resolve: (uuid, callback) => callback null, uuid }
        hydrantClient = new RedisNS @hydrantNamespace, redis.createClient(@redisUri)
        @hydrant = new MultiHydrantFactory {client: hydrantClient, uuidAliasResolver}

        @hydrant.on 'message', @_onHydrantMessage
        @hydrant.connect (error) =>
          debug 'hydrant connected!'
          debug {error}
          return callback(error) if error?
          @_bindQueue q, callback

    @meshbluMethods =
      'meshblu.request'          : @_meshbluRequest
      'meshblu.reply-to'         : @_meshbluReplyTo
      'meshblu.cache-auth'       : @_meshbluCacheAuth
      'meshblu.firehose.request' : @_meshbluFirehoseRequest

  _bindQueue: (q, callback=->) =>
    console.log 'queue connected'
    q.bind 'meshblu.request'
    q.bind 'meshblu.reply-to'
    q.bind 'meshblu.cache-auth'
    q.bind 'meshblu.firehose.request'
    callback()

    q.subscribe {
      ack: true
      prefetchCount: 1
    }, (message, headers, deliveryInfo, messageObject) =>
      console.log 'received message', message.data.toString()
      console.log {deliveryInfo}
      msg = JSON.parse message.data
      console.log deliveryInfo?.routingKey
      @meshbluMethods[deliveryInfo?.routingKey]?(msg, deliveryInfo)
      q.shift()

  _meshbluRequest: (msg, deliveryInfo) =>
    debug 'processing meshblu.request', msg
    jobs = []
    jobs.push @_fetchAuth unless msg?.job?.metadata?.auth?
    jobs.push @_fetchReplyTo unless msg?.jobInfo?.replyTo?
    jobs.push @_jobManagerDo
    async.applyEachSeries jobs, msg, deliveryInfo, (error, info) =>
      debug 'applied eachSeries'
      debug arguments
    # return @_jobManagerDo(msg) if msg.job.metadata?.auth?

  _fetchAuth: (msg, deliveryInfo, callback=->) =>
    debug 'fetching auth'
    @redisClient.hget deliveryInfo.consumerTag, 'auth', (error, auth) =>
      debug {error, auth}
      try
        auth = JSON.parse auth
      catch error
        auth = null
      msg.job.metadata.auth = auth
      callback error

  _fetchReplyTo: (msg, deliveryInfo, callback=->) =>
    debug 'fetching replyTo'
    @redisClient.hget deliveryInfo.consumerTag, 'replyTo', (error, replyTo) =>
      debug {error, replyTo}
      try
        replyTo = JSON.parse replyTo
      catch error
        replyTo = null
      msg.jobInfo.replyTo = replyTo
      callback error

  _jobManagerDo: (msg) =>
    debug 'doing request...', msg
    @jobManager.do 'request', 'response', msg.job, (error, response) =>
      debug 'response received:', response
      callbackId = msg.jobInfo.callbackId
      data = response.rawData
      if response.metadata.code >= 300
        data = response.metadata.status
        topic = 'error'
      replyTo = msg.jobInfo.replyTo
      reply = {topic, data, callbackId}
      debug {replyTo, reply}
      @connection.publish(replyTo, reply) if replyTo?

  _meshbluCacheAuth: (msg, deliveryInfo) =>
    debug 'caching ', msg.auth
    @redisClient.hset deliveryInfo.consumerTag, 'auth', JSON.stringify(msg.auth)

  _meshbluReplyTo: (msg, deliveryInfo) =>
    debug 'caching ', msg.replyTo
    @redisClient.hset deliveryInfo.consumerTag, 'replyTo', JSON.stringify(msg.replyTo)

  _meshbluFirehoseRequest: (msg) =>
    debug 'meshblu.firehose.request!'
    {uuid} = msg
    @hydrant.subscribe {uuid}, (error) =>
      debug 'firehose', {error}

  _onHydrantMessage: (uuid, message)=>
    debug onHydrantMessage: message
    message.topic = 'meshblu.firehose.request'
    @connection.publish("#{uuid}.firehose", message)

  run: (callback=->) =>
    debug 'inrun!'
    @connect()

module.exports = Worker
