fs = require 'fs'
rmdir = require 'rmdir'
ncp = require('ncp').ncp
sysPath = require 'path'
pkg = require '../package.json'

PUBLIC_ROOT = sysPath.resolve 'public'
PUBLIC_TEMPLATE_ROOT = sysPath.resolve sysPath.join('test', 'public')

FILES =
  'javascripts/app.js': 6
  'stylesheets/app.css': 0
  'index.html': 7

fileContent = (file, templateFile = no) ->
  path = if templateFile then PUBLIC_TEMPLATE_ROOT else PUBLIC_ROOT
  fs.readFileSync sysPath.join(path, file.replace '/', sysPath.sep), encoding: 'utf8'

replace = (plugin, source, map) ->
  newMap = {}
  # copy the map
  for key, value of map when map.hasOwnProperty(key)
    newMap[key] = "#{if value?.constructor is Function then value() else value}"
  newMap['date'] = plugin.getDateValue()
  newMap['timestamp'] = plugin.getTimestampValue()
  regexp = new RegExp "\\{\\!(#{Object.keys(newMap).join '|'})\\!\\}", 'g'
  source.replace regexp, (dummy, keyword) ->
    newMap[keyword]




describe 'Basic plugin behavdiour', ->
  it 'should be defined', ->
    expect(Plugin).to.be.ok

  it 'should not fail if no config', ->
    expect(-> new Plugin).to.not.throw()

  it 'should not do anything if no config given', ->
    plugin = new Plugin()
    spy = sinon.spy plugin, '_onCompile'
    plugin.onCompile()
    expect(spy).to.not.have.been.called

  it 'should call _onCompile when the config exists', ->
    plugin = new Plugin({ plugins: keyword: {} })
    spy = sinon.spy plugin, '_onCompile'
    plugin.onCompile()
    expect(spy).to.have.been.called



describe 'Replacing files\' content', ->
  plugin = null
  map =
    name: pkg.name
    version: pkg.version
    stringKey: 'testString'
    functionKey: -> 'testFunction'
  Object.freeze map

  beforeEach (done) ->
    filePattern = /\.(html|js)$/
    plugin = new Plugin plugins: { keyword: {filePattern, map} }
    ncp PUBLIC_TEMPLATE_ROOT, PUBLIC_ROOT, (err) ->
      throw err if err
      done()

  afterEach (done) ->
    plugin = null
    rmdir PUBLIC_ROOT, (err) ->
      throw err if err
      done()

  it 'should not throw errors', ->
    expect(-> plugin.onCompile []).to.not.throw()

  it 'should replace keywords only in files matching `filePattern`', ->
    plugin.onCompile()
    for file, included of FILES
      content = fileContent file
      templateContent = fileContent file, yes
      if included
        expectedContent = replace plugin, templateContent, map
      else
        expectedContent = templateContent
      expect(content).to.equal expectedContent

  it 'should produce valid compilation result', ->
    plugin.onCompile()
    expected = {}
    for file, count of FILES
      expected[sysPath.join PUBLIC_ROOT, file.replace('/', sysPath.sep)] = count
    expect(plugin.lastCompileResult).to.deep.equal(expected)
