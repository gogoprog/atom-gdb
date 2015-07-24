{BufferedProcess} = require 'atom'
{CompositeDisposable} = require 'atom'

module.exports = AtomGdb =
  atomGdbView: null
  modalPanel: null
  subscriptions: null
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
    console.log 'Starting debugger...'
    options =
      cwd: atom.config.get('atom-gdb.startupDirectory')
      env: process.env #not functional
    commandWords = atom.config.get('atom-gdb.debuggerCommand').split " "
    command = commandWords[0]
    args = commandWords[1..commandWords.length]
    args.push atom.config.get('atom-gdb.executablePath')
    stdout = (output) -> console.log("stdout:", output)
    stderr = (output) -> console.log("stderr:", output)
    exit = (return_code) -> console.log("Exit with ", return_code)
    process = new BufferedProcess({command, args, options, stdout, stderr, exit})

  toggle_breakpoint: ->
    console.log 'Breakpoint...'
    editor =  atom.workspace.getActiveTextEditor()
    console.log editor.getCursorBufferPosition().row + 1
