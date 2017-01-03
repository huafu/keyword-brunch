fs = require 'fs'
sysPath = require 'path'
RegExp.quote = require 'regexp-quote'


class KeywordProcessor
  @instance: null
  brunchPlugin: yes
  globalRE: null
  globalMap: null
  packageInfoFilePath: "package.json"
  lastCompileDate: null
  lastCompileResult: null


  constructor: (@config = {}) ->
    KeywordProcessor.instance = @
    return unless @config.plugins && @config.plugins.keyword
    path = sysPath.resolve(@config.paths?.public ? 'public')
    if (pip = @config.keyword?.jsonPackageFilePath)
      @packageInfoFilePath = pip
    if @packageInfoFilePath
      @packageInfoFilePath = fs.realpathSync(@packageInfoFilePath)
    @publicPath = path
    @keywordConfig = @config.plugins.keyword    
    @filePattern = @keywordConfig.filePattern ? /\.(js|css|html)$/
    @keywordMap = @keywordConfig.map ? {}


  generateDefaultMap: (compilationDate = new Date()) ->
    map = {}
    packageInfo = {}
    if fs.existsSync(@packageInfoFilePath)
      packageInfo = JSON.parse fs.readFileSync(@packageInfoFilePath).toString()
      for keyword in ["version", "name"]
        if packageInfo[keyword]
          map[keyword] = packageInfo[keyword]
        else
          console.error "#{sysPath.basename @packageInfoFilePath} need a #{keyword}"
    map['date'] = @getDateValue compilationDate
    map['timestamp'] = @getTimestampValue compilationDate
    map


  getDateValue: (compilationDate = @lastCompileDate) ->
    compilationDate.toUTCString()


  getTimestampValue: (compilationDate = @lastCompileDate) ->
    "#{compilationDate.getTime()}"



  readdirRecursive: (folder, callback) ->
    todo = 0
    doneCalled = no
    fileList = []
    done = (err) ->
      return if doneCalled
      doneCalled = yes
      if callback
        callback err, if err then [] else fileList
      else if err
        throw err
    check = (decr = no) ->
      todo-- if decr
      done() if todo is 0
    readOneDir = (folder) ->
      todo++
      fs.readdir folder, (err, files) ->
        if err
          done err
        else
          todo += files.length
          for file in files
            ((fullPath) ->
              fs.stat fullPath, (err, stat) ->
                if err
                  done err
                else
                  if stat.isDirectory()
                    todo--
                    readOneDir fullPath
                  else
                    fileList.push fullPath
                    check yes
            )(sysPath.join(folder, file))
          check yes
    readOneDir folder


  readdirRecursiveSync: (path, filterFunc = -> yes) ->
    unless fs.existsSync(path)
      return []
    unless fs.statSync(path).isDirectory()
      if filterFunc(sysPath.basename(path), sysPath.dirname(path))
        [path]
      else
        []
    else
      res = []
      for file in fs.readdirSync(path)
        fullPath = sysPath.join path, file
        if fs.statSync(fullPath).isDirectory()
          res = res.concat @readdirRecursiveSync(fullPath, filterFunc)
        else if filterFunc(file, path)
          res.push fullPath
      res


  computeUniqueFileList: (list, callback) ->
    todo = list.length
    doneCalled = no
    fileList = []
    done = (err) ->
      return if doneCalled
      doneCalled = yes
      if callback
        callback err, if err then [] else fileList
      else if err
        throw err
    check = (decr = no) ->
      todo-- if decr
      if todo is 0
        files = []
        for file in fileList
          files.push file if files.indexOf(file) is -1
        fileList = files
        done()
    readOneItem = (item) =>
      fs.realpath item, (err, resolvedPath) =>
        if err
          done err
        else
          fs.stat resolvedPath, (err, stat) =>
            if err
              done err
            else
              if stat.isDirectory()
                @readdirRecursive resolvedPath, (err, files) ->
                  if err
                    done err
                  else
                    fileList.push.apply fileList, files
                    check yes
              else
                fileList.push resolvedPath
                check yes
    for item in list
      readOneItem item
    check no


  computeUniqueFileListSync: (list) ->
    filesList = []
    filter = (file, path) -> filesList.indexOf(sysPath.join path, file) is -1
    for item in list
      filesList = filesList.concat @readdirRecursiveSync(item, filter)
    filesList



  processFiles: (fileList, callback) ->
    todo = 0
    processed = {}
    doneCalled = no

    done = (err = null) ->
      return if doneCalled
      doneCalled = yes
      if callback
        callback(err, processed)
      else if err
        throw err

    check = (decrease) ->
      todo-- if decrease
      done() if todo is 0

    @computeUniqueFileList fileList, (err, list) =>
      todo = list.length
      list.forEach (file) =>
        return if doneCalled
        @processFile file, (err, count) ->
          if err
            done err
          else
            processed["#{file}"] = count
            check yes


  processFilesSync: (fileList) ->
    changedFiles = {}
    for file in @computeUniqueFileListSync(fileList)
      changedFiles[file] = @processFileSync file
    changedFiles


  processFile: (file, callback) ->
    done = (err = null, count = 0) ->
      if err and not err instanceof Error
        err = new Error(err)
      if callback
        callback err, count
      else if err
        throw err

    fs.exists file, (exists) =>
      if exists
        if @filePattern.test file
          fs.readFile file, (err, data) =>
            if err
              done err
            else
              count = 0
              resultContent = data.toString()
              .replace @globalRE, (dummy, keyword) =>
                count++
                @globalMap[keyword]
              if count > 0
                fs.writeFile file, resultContent, (err) ->
                  done err, if err then 0 else count
              else
                done null, 0
        else
          done null
      else
        done "File #{file} does not exists."


  processFileSync: (file) ->
    if fs.existsSync(file)
      count = 0
      if @filePattern.test(file)
        content = fs.readFileSync(file)
        .toString()
        .replace @globalRE, (dummy, keyword) =>
          count++
          @globalMap[keyword]
      if count > 0
        fs.writeFileSync file, content
      count
    else
      throw new Error "File #{file} does not exists."


  prepareGlobalRegExp: (compileDate = new Date()) ->
    @globalMap = {}
    addMap = (map) =>
      for keyword, processor of map
        if processor instanceof Function
          replace = processor()
        else
          replace = processor
        @globalMap[keyword] = "#{replace}"
    addMap @generateDefaultMap compileDate
    addMap @keywordMap
    keywords = (RegExp.quote(key) for key, replacer of @globalMap)
    @globalRE = RegExp('\\{\\!(' + keywords.join('|') + ')\\!\\}', 'g')


  # we have a private version so that we can test in async mode using the
  # callback which isn't in the function signature of #onCompile in brunch
  # plugin API
  onCompile: (generatedFiles) ->
    if @keywordConfig
      @_onCompile generatedFiles


  _onCompile: (generatedFiles, callback = ->) ->
    @lastCompileDate = new Date()
    try
      @prepareGlobalRegExp @lastCompileDate
    catch e
      if callback
        callback e, {}
      else
        throw e
      return

    list = [@publicPath]
    if (extraFiles = @keywordConfig.extraFiles) and extraFiles.length
      list.push.apply list, extraFiles
    # waiting for brunch to have its onCompile function async, make the sync call instead
    #@processFiles list, ((err, result) -> @lasCompileResult = result if result; callback err, result)
    callback null, (@lastCompileResult = @processFilesSync list)





module.exports = KeywordProcessor
