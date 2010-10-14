CoreMeta = require './meta'
Utils = require './utils'

class Meta extends CoreMeta

  load: (options) ->
    super options, Meta.riakProperties.concat(Meta.queryProperties), Meta.defaults
      
  # HTTP response header mappings

  responseMappings:
    'content-type': 'contentType' # binary depends on the contentType
    'x-riak-vclock': 'vclock'
    'last-modified': 'lastMod'
    etag: 'etag'

    # other response info:
    # statusCode, X-Riak-Meta-* (=> usermeta), link (=> links) Location (=> key)
    # ignored headers: Vary, Server, Date, Content-Length, Transfer-Encoding

  loadResponse: (response) ->
    headers = response.headers
    
    # one-to-one
    for v,k of @responseMappings then this[k] = headers[v]
    
    # status code
    @statusCode = response.statusCode

    # usermeta
    for k,v of headers
      u = k.match /^X-Riak-Meta-(.*)/i
      @usermeta[u[1]] = v if u
    
    # links
    if headers.link then @links = linkUtils.stringToLinks headers.link
    
    # location
    if headers.location
      [$0, @raw, @bucket, @key] = headers.location.match /\/([^\/]+)\/([^\/]+)\/([^\/]+)/
    
    return this

  # HTTP request header mappings

  requestMappings:
    accept: 'Accept'
    host: 'Host'
    clientId: 'X-Riak-ClientId'
    vclock: 'X-Riak-Vclock'
    # lastMod: 'If-Modified-Since' # check possible bug with these
    # etag: 'If-None-Match' # check possible bug with these

    # other request info:
    # usermeta (X-Riak-Meta-*), links, contentType
    # ignored info: binary, raw, url, path
    
  toHeaders: ->
    headers = {}
    
    for k,v of @requestMappings then headers[v] = this[k] if this[k]
    
    # usermeta
    for k,v of @usermeta then headers["X-Riak-Meta-#{k}"] = String(v)
    
    # links
    headers['Link'] = linkUtils.linksToString(@links, @raw) if @links.length > 0
    
    # contentType (only if data is present)
    headers['Content-Type'] = @contentType if @data?

    return headers
  

Meta::__defineGetter__ 'path', ->
  queryString = @stringifyQuery @queryProps
  "/#{@raw}/#{@bucket or ''}/#{@key or ''}#{if queryString then '?' + queryString else ''}"

Meta::__defineGetter__ 'queryProps', ->
  queryProps = {}
  Meta.queryProperties.forEach (prop) => queryProps[prop] = this[prop] if this[prop]?
  queryProps
  
Meta.defaults =
  host: 'localhost'
  accept: 'multipart/mixed, application/json;q=0.7, */*;q=0.5'

Meta.queryProperties = ['r', 'w', 'dw', 'rw', 'keys', 'props', 'vtag', 'returnbody', 'chunked']

Meta.riakProperties = [
  'statusCode'
  'host'
  'responseEncoding'
]

module.exports = Meta

# private

linkUtils =
  stringToLinks: (links) ->
    result = []
    if links
      links.split(',').forEach (link) ->
        captures = link.trim().match /^<\/([^\/]+)\/([^\/]+)\/([^\/]+)>;\sriaktag="(.+)"$/
        if captures
          for i of captures then captures[i] = decodeURIComponent(captures[i])
          result.push { bucket: captures[2], key: captures[3], tag: captures[4] }
    result
    
  linksToString: (links, raw) ->
    links = if Array.isArray(links) then links else [links]
    links.map((link) => "</#{raw}/#{encodeURIComponent link.bucket}/#{encodeURIComponent link.key}>; riaktag=\"#{encodeURIComponent link.tag || "_"}\"").join ", "