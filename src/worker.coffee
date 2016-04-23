debug                 = require('debug')('meshblu-core-worker-mqtt:worker')
RedisPooledJobManager = require 'meshblu-core-redis-pooled-job-manager'
uuid                  = require 'uuid'
_                     = require 'lodash'

class Worker
  constructor: (options={}, dependencies={})->
    # super wildcard: true
    @queueName = "#{options.uuid}.#{uuid.v4()}"
    # @firehoseQueueName = "#{options.uuid}.firehose.#{uuid.v4()}"
    @mqtt = dependencies.mqtt ? require 'mqtt'
    {uuid,token} = options
    console.log options
    console.log {uuid,token}
    defaults =
      keepalive: 10
      protocolId: 'MQIsdp'
      protocolVersion: 3
      qos: 0
      username: options.uuid
      password: options.token
      reconnectPeriod: 5000
      clientId: @queueName
    @options = _.defaults options, defaults
    @messageCallbacks = {}

    @JOB_MAP =
      'meshblu.generateAndStoreToken': @handleEvent
      'meshblu.getPublicKey':          @handleEvent
      'meshblu.message':               @handleEvent
      'meshblu.resetToken':            @handleEvent
      'meshblu.update':                @handleEvent
      'meshblu.whoami':                @handleEvent

  connect: (callback=->) =>
    uri = @_buildUri()

    @client = @mqtt.connect uri, @options
    @client.once 'connect', =>
      response = _.pick @options, 'uuid', 'token'
      # @client.subscribe @firehoseQueueName, qos: @options.qos
      console.log _.keys @JOB_MAP
      _.each _.keys(@JOB_MAP), (job) =>
        console.log "subscribing to #{job}"
        @client.subscribe job, qos: @options.qos
      callback response

    @client.on 'message', @_messageHandler

    # _.each PROXY_EVENTS, (event) => @_proxy event

  run: (callback=->) =>
    @connect()
    #callback

  publish: (topic, data, callback=->) =>
    throw new Error 'No Active Connection' unless @client?

    if !data
      rawData = null
    else if _.isString data
      rawData = data
    else
      data.callbackId = uuid.v4();
      @messageCallbacks[data.callbackId] = callback;
      rawData = JSON.stringify(data)
    debug 'publish', topic, rawData
    @client.publish 'meshblu.'+topic, rawData

  # API Functions
  message: (params, callback=->) =>
    @publish 'message', params, callback

  subscribe: (params, callback=->) =>
    @client.subscribe params

  unsubscribe: (params, callback=->) =>
    @client.unsubscribe params

  update: (data, callback=->) =>
    @publish 'update', data, callback

  resetToken: (data, callback=->) =>
    @publish 'resetToken', data, callback

  getPublicKey: (data, callback=->) =>
    @publish 'getPublicKey', data, callback

  generateAndStoreToken: (data, callback=->) =>
    @publish 'generateAndStoreToken', data, callback

  whoami: (callback=->) =>
    @publish 'whoami', {}, callback

  # Private Functions
  _buildUri: =>
    defaults =
      protocol: 'mqtt'
      hostname: 'meshblu.octoblu.com'
      port: 1883
    uriOptions = _.defaults {}, @options, defaults
    uri = uriOptions.protocol + ':' + uriOptions.hostname + ':' + uriOptions.port
    # uri = url.format uriOptions
    console.log uri
    return uri

  _messageHandler: (uuid, message, packet) =>
    packet.payload = packet.payload.toString()
    debug {uuid, message: message.toString(), packet}

    message = message.toString()
    try
      message = JSON.parse message
    catch error
      debug 'unable to parse message', message

    debug "sending a response to #{message.queueName}"
    return @client.publish message.queueName, JSON.stringify(hello: 'world')

    debug '_messageHandler', message.topic, message.data
    return if @handleCallbackResponse message
    # return @emit message.topic, message.data

  handleCallbackResponse: (message) =>
    id = message._request?.callbackId
    return false unless id?
    callback = @messageCallbacks[id] ? ->
    callback message.data if message.topic == 'error'
    callback null, message.data if message.topic != 'error'
    delete @messageCallbacks[id]
    return true

  _proxy: (event) =>
    @client.on event, =>
      debug 'proxy ' + event, _.first arguments
      # @emit event, arguments...

  _uuidOrObject: (data) =>
    return uuid: data if _.isString data
    return data

  handleEvent: (packet) =>
    console.log packet

module.exports = Worker
