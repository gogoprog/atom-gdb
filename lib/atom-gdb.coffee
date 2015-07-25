{BufferedProcess} = require 'atom'
{CompositeDisposable} = require 'atom'
path = require 'path'
fs = require 'fs'
remote = require "remote"
dialog = remote.require "dialog"

module.exports = AtomGdb =
  atomGdbView: null
  modalPanel: null
  subscriptions: null
  breakPoints: []
  markers: {}
  settings: {}
  config:
    debuggerCommand:
      type: 'string'
      default: 'qtcreator -client -debug'

  activate: (state) ->
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-gdb:start': => @start()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-gdb:select-executable': => @selectExecutable()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-gdb:select-startup-directory': => @selectStartupDirectory()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'atom-gdb:toggle_breakpoint': => @toggle_breakpoint()

  deactivate: ->
    @subscriptions.dispose()

  serialize: ->

  getStartupPath: ->
    path = atom.config.get('atom-gdb.startupDirectory')
    path = atom.project.getPaths()[0] if path == ""
    return path

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

    @settings['executablePath'] = value
    return value != undefined

  selectStartupDirectory: ->
    value = dialog.showOpenDialog
      properties: [ 'openDirectory' ]
      title: "Select the startup directory"
      defaultPath: atom.project.getPaths()[0]

    @settings['startupDirectory'] = value[0]
    return value != undefined

  start: ->
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

    args.push exe
    @runProcess(command, args, cwd)

  toggle_breakpoint: ->
    editor = atom.workspace.getActiveTextEditor()
    filename = path.basename(editor.getPath())
    row = Number(editor.getCursorBufferPosition().row + 1)
    key = filename + ":" + row
    index = @breakPoints.indexOf(key)
    if index == -1
      @breakPoints.push key
      range = editor.getSelectedBufferRange()
      marker = editor.markBufferRange(range, {invalidate: 'never'})
      editor.decorateMarker(marker, {type: 'line-number', class: 'breakpoint'})
      @markers[key] = marker
      marker.key = key
      marker.filename = filename

      bps = @breakPoints

      marker.onDidChange (event) ->
        old_line = event.oldHeadBufferPosition.row + 1
        new_line = event.newHeadBufferPosition.row + 1
        new_key = marker.filename + ':' + new_line
        bps.splice(bps.indexOf(marker.key), 1)
        bps.push new_key
        marker.key = new_key
        AtomGdb.updateGdbInit()
        console.log("Moved breakpoint:", filename, ":", old_line, "to", new_line)
        return

      console.log("Added breakpoint:", filename, ":", row)
    else
      @breakPoints.splice(index, 1)
      @markers[key].destroy()
      console.log("Removed breakpoint:", filename, ":", row)

    @updateGdbInit()

  updateGdbInit: ->
    cwd = @getSetting('startupDirectory')
    if cwd == ""
      @updateGdbInit() if @selectStartupDirectory()
      return
    process.chdir cwd
    outputFile = fs.createWriteStream(".gdbinit")
    bps = @breakPoints
    outputFile.on 'open', (fd) ->
      outputFile.write "set breakpoint pending on\n"
      outputFile.write "b " + bp + "\n" for bp in bps
      outputFile.end()
      return
