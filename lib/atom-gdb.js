var AtomGdb, BufferedProcess, CompositeDisposable, File, dialog, fs, path;

BufferedProcess = require('atom').BufferedProcess;

CompositeDisposable = require('atom').CompositeDisposable;

File = require('atom').File;

path = require('path');

fs = require('fs');

dialog = require('remote').dialog;

module.exports = AtomGdb = {
    atomGdbView: null,
    modalPanel: null,
    subscriptions: null,
    breakpoints: [],
    markers: {},
    settings: {},
    settingsFile: null,
    childProcess: null,
    config: {
        debuggerCommand: {
            type: 'string',
            "default": 'qtcreator -client -debug'
        },
        executableSuffix: {
            type: 'string',
            "default": ''
        },
        saveOnStart: {
            type: 'boolean',
            "default": true
        }
    },
    activate: function(state) {
        this.subscriptions = new CompositeDisposable;
        this.subscriptions.add(atom.commands.add('atom-workspace', {
            'atom-gdb:start': (function(_this) {
                return function() {
                    return _this.start();
                };
            })(this)
        }));
        this.subscriptions.add(atom.commands.add('atom-workspace', {
            'atom-gdb:start-no-debug': (function(_this) {
                return function() {
                    return _this.startNoDebug();
                };
            })(this)
        }));
        this.subscriptions.add(atom.commands.add('atom-workspace', {
            'atom-gdb:stop': (function(_this) {
                return function() {
                    return _this.stopChildProcess();
                };
            })(this)
        }));
        this.subscriptions.add(atom.commands.add('atom-workspace', {
            'atom-gdb:select-executable': (function(_this) {
                return function() {
                    return _this.selectExecutable();
                };
            })(this)
        }));
        this.subscriptions.add(atom.commands.add('atom-workspace', {
            'atom-gdb:select-startup-directory': (function(_this) {
                return function() {
                    return _this.selectStartupDirectory();
                };
            })(this)
        }));
        this.subscriptions.add(atom.commands.add('atom-text-editor', {
            'atom-gdb:toggle-breakpoint': (function(_this) {
                return function() {
                    return _this.toggleBreakpoint();
                };
            })(this)
        }));
        this.handleSettingsFile();
        this.checkGlobalGdbInit();
        return atom.workspace.onDidOpen(function(event) {
            var editor, i, item, marker, results;
            if (event.uri !== void 0) {
                results = [];
                for (i in AtomGdb.breakpoints) {
                    item = AtomGdb.breakpoints[i];
                    if (item.filepath === event.uri) {
                        editor = atom.workspace.getActiveTextEditor();
                        marker = editor.markBufferPosition([item.line - 1, 0], {
                            invalidate: 'never'
                        });
                        results.push(AtomGdb.setupMarker(marker, item));
                    } else {
                        results.push(void 0);
                    }
                }
                return results;
            }
        });
    },
    deactivate: function() {
        return this.subscriptions.dispose();
    },
    getStartupPath: function() {
        var _path;
        _path = atom.config.get('atom-gdb.startupDirectory');
        if (_path === "") {
            _path = atom.project.getPaths()[0];
        }
        return _path;
    },
    getSetting: function(name) {
        if (!(name in this.settings) || this.settings[name] === void 0) {
            this.settings[name] = "";
        }
        return this.settings[name];
    },
    runProcess: function(command, args, cwd) {
        var exit, stderr, stdout;
        var that = this;
        stdout = function(output) {
            return console.log("stdout:", output);
        };
        stderr = function(output) {
            return console.log("stderr:", output);
        };
        exit = function(return_code) {
            that.childProcess = null;
            return console.log("Exit with ", return_code);
        };
        console.log('Starting process :', command, args.join(" "), 'in', cwd);
        process.chdir(cwd);
        return this.childProcess = new BufferedProcess({
            command: command,
            args: args,
            stdout: stdout,
            stderr: stderr,
            exit: exit
        });
    },
    selectExecutable: function() {
        var value;
        value = dialog.showOpenDialog({
            properties: ['openFile'],
            title: "Select the binary to debug",
            defaultPath: atom.project.getPaths()[0]
        });
        if (value !== void 0) {
            this.settings['executablePath'] = value[0];
            this.updateSettingsFile();
        }
        return value !== void 0;
    },
    selectStartupDirectory: function() {
        var value;
        value = dialog.showOpenDialog({
            properties: ['openDirectory'],
            title: "Select the startup directory",
            defaultPath: atom.project.getPaths()[0]
        });
        if (value !== void 0) {
            this.settings['startupDirectory'] = value[0];
            this.updateSettingsFile();
        }
        return value !== void 0;
    },
    start: function() {
        var args, command, commandWords, cwd, exe;
        if (atom.config.get('atom-gdb.saveOnStart')) {
            this.saveAll();
        }
        commandWords = atom.config.get('atom-gdb.debuggerCommand').split(" ");
        command = commandWords[0];
        args = commandWords.slice(1, +commandWords.length + 1 || 9e9);
        exe = this.getSetting('executablePath');
        if (exe === "") {
            if (this.selectExecutable()) {
                this.start();
            }
            return;
        }
        cwd = this.getSetting('startupDirectory');
        if (cwd === "") {
            if (this.selectStartupDirectory()) {
                this.start();
            }
            return;
        }
        args.push(exe + atom.config.get('atom-gdb.executableSuffix'));
        return this.runProcess(command, args, cwd);
    },
    startNoDebug: function() {
        var command, cwd, exe;
        if (atom.config.get('atom-gdb.saveOnStart')) {
            this.saveAll();
        }
        exe = this.getSetting('executablePath');
        if (exe === "") {
            if (this.selectExecutable()) {
                this.startNoDebug();
            }
            return;
        }
        cwd = this.getSetting('startupDirectory');
        if (cwd === "") {
            if (this.selectStartupDirectory()) {
                this.startNoDebug();
            }
            return;
        }
        command = exe;
        return this.runProcess(command, [], cwd);
    },
    stopChildProcess: function() {
        if(this.childProcess != null) {
            require('tree-kill')(this.childProcess.process.pid, 'SIGKILL');
            this.childProcess = null;
        }
    },
    toggleBreakpoint: function() {
        var editor, index, item, marker, range;
        editor = atom.workspace.getActiveTextEditor();
        item = {
            filepath: editor.getPath(),
            filename: path.basename(editor.getPath()),
            line: Number(editor.getCursorBufferPosition().row + 1)
        };
        index = this.findBreakpointIndex(item);
        if (index === -1) {
            this.breakpoints.push(item);
            range = editor.getSelectedBufferRange();
            marker = editor.markBufferRange(range, {
                invalidate: 'never'
            });
            this.setupMarker(marker, item);
            console.log("Added breakpoint:", item.filename, ":", item.line);
        } else {
            this.breakpoints.splice(index, 1);
            this.markers[this.generateKey(item)].destroy();
            console.log("Removed breakpoint:", item.filename, ":", item.line);
        }
        return this.updateGdbInit();
    },
    setupMarker: function(marker, item) {
        var bps, editor;
        editor = atom.workspace.getActiveTextEditor();
        editor.decorateMarker(marker, {
            type: 'line-number',
            "class": 'syntax--breakpoint'
        });
        this.markers[this.generateKey(item)] = marker;
        marker.item = item;
        bps = this.breakpoints;
        return marker.onDidChange(function(event) {
            var new_line, old_line;
            old_line = event.oldHeadBufferPosition.row + 1;
            new_line = event.newHeadBufferPosition.row + 1;
            marker.item.line = new_line;
            AtomGdb.updateGdbInit();
            console.log("Moved breakpoint:", item.filename, ":", old_line, "to", new_line);
        });
    },
    updateGdbInit: function() {
        var bps, cwd, outputFile;
        cwd = this.getSetting('startupDirectory');
        if (cwd === "") {
            if (this.selectStartupDirectory()) {
                this.updateGdbInit();
            }
            return;
        }
        process.chdir(cwd);
        outputFile = fs.createWriteStream(".gdbinit");
        bps = this.breakpoints;
        return outputFile.on('open', function(fd) {
            var item, j, len;
            outputFile.write("set breakpoint pending on\n");
            for (j = 0, len = bps.length; j < len; j++) {
                item = bps[j];
                outputFile.write("b " + AtomGdb.generateKey(item) + "\n");
            }
            outputFile.end();
        });
    },
    handleSettingsFile: function() {
        var _path;
        _path = atom.project.getPaths()[0];
        this.settingsFile = new File(_path + "/.atom-gdb.json", false);
        if (this.settingsFile.exists()) {
            this.settingsFile.read().then(function(content) {
                AtomGdb.settings = JSON.parse(content);
                if (AtomGdb.settings === null) {
                    return AtomGdb.settings = {};
                }
            });
        } else {
            this.settingsFile.create();
        }
        return this.settingsFile.onDidChange(function() {
            return AtomGdb.settingsFile.read().then(function(content) {
                AtomGdb.settings = JSON.parse(content);
                if (AtomGdb.settings === null) {
                    return AtomGdb.settings = {};
                }
            });
        });
    },
    updateSettingsFile: function() {
        return this.settingsFile.write(JSON.stringify(this.settings, null, 2));
    },
    generateKey: function(item) {
        return item.filename + ":" + item.line;
    },
    findBreakpointIndex: function(_item) {
        var i, item, length;
        i = 0;
        length = this.breakpoints.length;
        while (i < length) {
            item = this.breakpoints[i];
            if (item.filepath === _item.filepath && item.line === _item.line) {
                return i;
            }
            ++i;
        }
        return -1;
    },
    saveAll: function() {
        var editors, i, results;
        editors = atom.workspace.getTextEditors();
        results = [];
        for (i in editors) {
            results.push(editors[i].save());
        }
        return results;
    },
    checkGlobalGdbInit: function() {
        var globalGdbInitFile;
        globalGdbInitFile = new File(process.env['HOME'] + "/.gdbinit", false);
        return globalGdbInitFile.read().then(function(content) {
            if (content === null || !content.match(/^set auto-load safe-path/m)) {
                globalGdbInitFile.write((content || "") + "\n# Added by atom-gdb\nset auto-load safe-path /");
                return console.log("~/.gdbinit has been updated for atom-gdb");
            } else {
                return console.log("~/.gdbinit is fine for atom-gdb");
            }
        });
    }
};
