{BufferedProcess} = require 'atom'
{CompositeDisposable} = require 'atom'
{File} = require 'atom'
path = require 'path'
fs = require 'fs'
{dialog} = require 'remote'

module.exports = AtomGdb =
  atomGdbView: null
  modalPanel: null
  subscriptions: null
  breakpoints: []
  markers: {}
  settings: {}
  settingsFile: null
  config:
    debuggerCommand:
      type: 'string'
      default: 'qtcreator -client -debug'
    executableSuffix:
      type: 'string'
      default: ''
    saveOnStart:
      type:'boolean'
      default:true

  activate: (state) ->
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-gdb:start': => @start()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-gdb:start-no-debug': => @startNoDebug()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-gdb:select-executable': => @selectExecutable()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-gdb:select-startup-directory': => @selectStartupDirectory()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'atom-gdb:toggle-breakpoint': => @toggleBreakpoint()

    @handleSettingsFile()
    @checkGlobalGdbInit()

    atom.workspace.onDidOpen (event)->
      if event.uri != undefined
        for i of AtomGdb.breakpoints
          item = AtomGdb.breakpoints[i]
          if item.filepath == event.uri
            editor = atom.workspace.getActiveTextEditor()
            marker = editor.markBufferPosition([item.line-1, 0], {invalidate: 'never'})
            AtomGdb.setupMarker(marker, item)

  deactivate: ->
    @subscriptions.dispose()

  getStartupPath: ->
    _path = atom.config.get('atom-gdb.startupDirectory')
    _path = atom.project.getPaths()[0] if _path == ""
    return _path

  getSetting: (name) ->
    @settings[name] = "" if (name not of @settings or @settings[name] == undefined)
    return @settings[name]

  runProcess:  (command, args, cwd) ->
    stdout = (output) -> console.log("stdout:", output)
    stderr = (output) -> console.log("stderr:", output)
    exit = (return_code) -> console.log("Exit with ", return_code)
    console.log 'Starting process :', command, args.join(" "), 'in', cwd
    process.chdir cwd
    childProcess = new BufferedProcess({command, args, stdout, stderr, exit})

  selectExecutable: ->
    value = dialog.showOpenDialog
      properties: [ 'openFile' ]
      title: "Select the binary to debug"
      defaultPath: atom.project.getPaths()[0]

    if value != undefined
      @settings['executablePath'] = value[0]
      @updateSettingsFile()

    return value != undefined

  selectStartupDirectory: ->
    value = dialog.showOpenDialog
      properties: [ 'openDirectory' ]
      title: "Select the startup directory"
      defaultPath: atom.project.getPaths()[0]

    if value != undefined
      @settings['startupDirectory'] = value[0]
      @updateSettingsFile()

    return value != undefined

  start: ->
    @saveAll() if atom.config.get('atom-gdb.saveOnStart')
    commandWords = atom.config.get('atom-gdb.debuggerCommand').split " "
    command = commandWords[0]
    args = commandWords[1..commandWords.length]

    exe = @getSetting('executablePath')
    if exe == ""
      @start() if @selectExecutable()
      return

    cwd = @getSetting('startupDirectory')
    if cwd == ""
      @start() if @selectStartupDirectory()
      return

    args.push (exe+atom.config.get('atom-gdb.executableSuffix'))
    @runProcess(command, args, cwd)

  startNoDebug: ->
    @saveAll() if atom.config.get('atom-gdb.saveOnStart')
    exe = @getSetting('executablePath')
    if exe == ""
      @start() if @selectExecutable()
      return

    cwd = @getSetting('startupDirectory')
    if cwd == ""
      @start() if @selectStartupDirectory()
      return

    command = exe
    @runProcess(command, [], cwd)

  toggleBreakpoint: ->
    editor = atom.workspace.getActiveTextEditor()
    item =
      filepath: editor.getPath()
      filename: path.basename(editor.getPath())
      line: Number(editor.getCursorBufferPosition().row + 1)

    index = @findBreakpointIndex(item)
    if index == -1
      @breakpoints.push item
      range = editor.getSelectedBufferRange()
      marker = editor.markBufferRange(range, {invalidate: 'never'})

      @setupMarker(marker, item)

      console.log("Added breakpoint:", item.filename, ":", item.line)
    else
      @breakpoints.splice(index, 1)
      @markers[@generateKey(item)].destroy()
      console.log("Removed breakpoint:", item.filename, ":", item.line)

    @updateGdbInit()

  setupMarker: (marker, item) ->
    editor = atom.workspace.getActiveTextEditor()
    editor.decorateMarker(marker, {type: 'line-number', class: 'syntax--breakpoint'})
    @markers[@generateKey(item)] = marker
    marker.item = item

    bps = @breakpoints

    marker.onDidChange (event) ->
      old_line = event.oldHeadBufferPosition.row + 1
      new_line = event.newHeadBufferPosition.row + 1
      marker.item.line = new_line
      AtomGdb.updateGdbInit()
      console.log("Moved breakpoint:", item.filename, ":", old_line, "to", new_line)
      return

  updateGdbInit: ->
    cwd = @getSetting('startupDirectory')
    if cwd == ""
      @updateGdbInit() if @selectStartupDirectory()
      return
    process.chdir cwd
    outputFile = fs.createWriteStream(".gdbinit")
    bps = @breakpoints
    outputFile.on 'open', (fd) ->
      outputFile.write "set breakpoint pending on\n"
      outputFile.write "b " + AtomGdb.generateKey(item) + "\n" for item in bps
      outputFile.end()
      return

  handleSettingsFile: ->
    _path = atom.project.getPaths()[0]
    @settingsFile = new File(_path+"/.atom-gdb.json", false)
    if @settingsFile.exists()
      @settingsFile.read()
        .then (content) ->
          AtomGdb.settings = JSON.parse(content)
          AtomGdb.settings = {} if AtomGdb.settings == null
    else
      @settingsFile.create()

    @settingsFile.onDidChange ->
      AtomGdb.settingsFile.read()
        .then (content) ->
          AtomGdb.settings = JSON.parse(content)
          AtomGdb.settings = {} if AtomGdb.settings == null

  updateSettingsFile: ->
    @settingsFile.write(JSON.stringify(@settings, null, 2))

  generateKey: (item) ->
      return item.filename + ":" + item.line

  findBreakpointIndex: (_item) ->
    i = 0
    length = @breakpoints.length
    while i < length
      item = @breakpoints[i]
      if item.filepath == _item.filepath and item.line == _item.line
        return i
      ++i
    return -1

  saveAll: ->
    editors = atom.workspace.getTextEditors()
    for i of editors
      editors[i].save()

  checkGlobalGdbInit: ->
    globalGdbInitFile = new File(process.env['HOME'] + "/.gdbinit", false)
    globalGdbInitFile.read()
      .then (content) ->
        if content == null or not content.match /^set auto-load safe-path/m
          globalGdbInitFile.write (content or "") + "\n# Added by atom-gdb\nset auto-load safe-path /"
          console.log "~/.gdbinit has been updated for atom-gdb"
        else
          console.log "~/.gdbinit is fine for atom-gdb"
