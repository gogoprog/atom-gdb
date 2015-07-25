{BufferedProcess} = require 'atom'
{CompositeDisposable} = require 'atom'
path = require 'path'
fs = require 'fs'

module.exports = AtomGdb =
  atomGdbView: null
  modalPanel: null
  subscriptions: null
  breakPoints: []
  markers: {}
  config:
    debuggerCommand:
      type: 'string'
      default: 'qtcreator -client -debug'
    startupDirectory:
      type: 'string'
      default: '/home'
    executablePath:
      type: 'string'
      default: ''

  activate: (state) ->
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-gdb:start': => @start()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'atom-gdb:toggle_breakpoint': => @toggle_breakpoint()

  deactivate: ->
    @subscriptions.dispose()

  serialize: ->

  start: ->
    commandWords = atom.config.get('atom-gdb.debuggerCommand').split " "
    command = commandWords[0]
    args = commandWords[1..commandWords.length]
    cwd = atom.config.get('atom-gdb.startupDirectory')
    args.push atom.config.get('atom-gdb.executablePath')
    stdout = (output) -> console.log("stdout:", output)
    stderr = (output) -> console.log("stderr:", output)
    exit = (return_code) -> console.log("Exit with ", return_code)
    process.chdir cwd
    console.log 'Starting debugger :', command, args.join(" "), 'in', cwd
    childProcess = new BufferedProcess({command, args, stdout, stderr, exit})

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
      console.log("Added breakpoint:", filename, ":", row)
    else
      @breakPoints.splice(index, 1)
      @markers[key].destroy()
      console.log("Removed breakpoint:", filename, ":", row)

    @updateGdbInit()

  updateGdbInit: ->
    process.chdir atom.config.get('atom-gdb.startupDirectory')
    outputFile = fs.createWriteStream(".gdbinit")
    bps = @breakPoints
    outputFile.on 'open', (fd) ->
      outputFile.write "set breakpoint pending on\n"
      outputFile.write "b " + bp + "\n" for bp in bps
      outputFile.end()
      return
