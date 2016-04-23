_      = require 'lodash'
Worker = require './src/worker'

class Command
  constructor: ->
    @options =
      # redisUri         : process.env.REDIS_URI
      # namespace        : process.env.NAMESPACE || 'meshblu'
      uuid             : process.env.MESHBLU_UUID
      token            : process.env.MESHBLU_TOKEN
      hostname         : process.env.MESHBLU_HOSTNAME
      jobTimeoutSeconds: parseInt(process.env.JOB_TIMEOUT_SECONDS || 30)
      maxConnections   : parseInt(process.env.CONNECTION_POOL_MAX_CONNECTIONS || 100)
      jobLogRedisUri   : process.env.JOB_LOG_REDIS_URI
      jobLogQueue      : process.env.JOB_LOG_QUEUE
      jobLogSampleRate : parseFloat(process.env.JOB_LOG_SAMPLE_RATE)

  panic: (error) =>
    console.error error.stack
    process.exit 1

  run: =>
    # @panic new Error('Missing required environment variable: mqtt_URI') if _.isEmpty @options.mqttUri
    # @panic new Error('Missing required environment variable: REDIS_URI') if _.isEmpty @options.redisUri
    # @panic new Error('Missing required environment variable: JOB_LOG_REDIS_URI') if _.isEmpty @options.jobLogRedisUri
    # @panic new Error('Missing required environment variable: JOB_LOG_QUEUE') if _.isEmpty @options.jobLogQueue
    # @panic new Error('Missing required environment variable: JOB_LOG_SAMPLE_RATE') unless _.isNumber @options.jobLogSampleRate

    worker = new Worker @options

    console.log 'mqtt worker is working'

    worker.run (error) =>
      return @panic error if error?

    process.on 'SIGTERM', =>
      console.log 'SIGTERM caught, exiting'
      worker.stop =>
        process.exit 0

command = new Command()
command.run()
