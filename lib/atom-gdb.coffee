{BufferedProcess} = require 'atom'
{CompositeDisposable} = require 'atom'

module.exports = AtomGdb =
  atomGdbView: null
  modalPanel: null
  subscriptions: null

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
    command = 'zenity'
    args = ['--error']
    stdout = (output) -> console.log(output)
    process = new BufferedProcess({command, args, stdout})

  toggle_breakpoint: ->
    console.log 'Breakpoint...'
    editor =  atom.workspace.getActiveTextEditor()
    console.log editor.getCursorBufferPosition().row + 1
