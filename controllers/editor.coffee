util = require 'util'

EditorInterface = require '../lib/editor_interface'

# An Editor represents a socket.io connection from the web editor.
# It handles editor messages.
class Editor

  constructor: (@db, @socket) ->
    @editorInterface = new EditorInterface @db

    @socket.on 'disconnect', @onDisconnect
    @socket.on 'get_tree', @onGetTree

  # fires when a socket disconnects, either by the client closing the connection
  # or calling the `disconnect` method of the socket.
  onDisconnect: =>

  onGetTree: (data, fn) =>
    fn @editorInterface.objectsTree()

# This is the editor controller.
# It handles socket.io connections from the editor.
module.exports = class EditorController

  constructor: (io, db) ->
    io.of('/editor').on 'connection', (socket) ->
      address = socket.handshake.address
      util.log "new editor connection from #{address.address}:#{address.port}"
      new Editor db, socket