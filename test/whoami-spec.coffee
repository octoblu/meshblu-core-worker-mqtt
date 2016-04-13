Worker      = require '../src/worker'
MeshbluAmqp = require 'meshblu-amqp'
RedisNS     = require '@octoblu/redis-ns'
redis       = require 'ioredis'
JobManager  = require 'meshblu-core-job-manager'
async       = require 'async'


describe 'whoami', ->
  beforeEach ->
    @jobManager = new JobManager
      client: new RedisNS 'ns', redis.createClient()
      timeoutSeconds: 1

  beforeEach ->
    @worker = new Worker
      amqpUri: 'amqp://meshblu:judgementday@127.0.0.1'
      jobTimeoutSeconds: 1
      jobLogRedisUri: 'redis://localhost:6379'
      jobLogQueue: 'sample-rate:0.00'
      jobLogSampleRate: 0
      maxConnections: 10
      redisUri: 'redis://localhost:6379'
      namespace: 'ns'

    @worker.run (error) =>
      throw error if error?

  beforeEach (done) ->
    @client = new MeshbluAmqp uuid: 'some-uuid', token: 'some-token', hostname: 'localhost'
    @client.connect done

  beforeEach (done) ->

    @asyncJobManagerGetRequest = (callback) =>
      @jobManager.getRequest ['request'], (error, @jobManagerRequest) =>
        return callback error if error?
        return callback new Error('Request timeout') unless @jobManagerRequest?
        console.log {@jobManagerRequest}

        responseOptions =
          metadata:
            responseId: @jobManagerRequest.metadata.responseId
          data: { whoami:'somebody' }
          code: 200

        @jobManager.createResponse 'response', responseOptions, (error) =>
          console.log 'INRESPONSE CALLBACK', error
          callback()

    @asyncClientWhoAmi = (callback) =>
      @client.whoami (error, @data) =>
        console.log 'IN WHOAMI CALLBACK', error
        callback(error)

    async.parallel [ @asyncJobManagerGetRequest, @asyncClientWhoAmi ], done

  it 'should create a @jobManagerRequest', (done) ->
    expect(@jobManagerRequest.metadata.jobType).to.deep.equal 'GetDevice'

  # describe 'when the dispatcher responds', ->
  #   beforeEach (done) ->
  #     @connection.once 'whoami', (@response) => done()
  #
  #     @jobManager.getRequest ['request'], (error,request) =>
  #       return done error if error?
  #       return done new Error('Request timeout') unless request?
  #
  #       response =
  #         metadata:
  #           responseId: request.metadata.responseId
  #           code: 200
  #         data:
  #           uuid: 'OHM MY!! WATT HAPPENED?? VOLTS'
  #       @jobManager.createResponse 'response', response, (error) =>
  #         return done error if error?
  #
  #
  # it 'should give us a device', ->
  #   expect(@data).to.exist
