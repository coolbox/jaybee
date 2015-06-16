# Collections
#
@PlaylistTracks = new Meteor.Collection("playlist_tracks")
@PlayedTracks = new Meteor.Collection("played_tracks")
@Masters = new Meteor.Collection("masters")

# Subscribes
if Meteor.isClient
  @accessTokenDep = new Deps.Dependency

  # Init custom classes
  @player = new Player
  @search = new Search

  # Set NowPlaying Track
  # Sometimes there is one in the playlist, but it's
  # not set on the UI.
  # This sets it on the UI.
  Meteor.call "nowPlaying", (error, track) ->
    @player.markAsNowPlaying track if track

  # Subscriptions
  # Docs: https://www.meteor.com/try/11
  Meteor.subscribe "masters"
  Meteor.subscribe "playlist_tracks"

  Meteor.subscribe 'SC.OAuth', ->
    if Meteor.user()
      # Set Access Token
      accessToken = Meteor.user().services.soundcloud.accessToken
      if accessToken
        accessTokenDep.changed()
        SC.accessToken accessToken

        # Get and set favorites
        player.getFavorites()

  # Track shit to publish to everyone! \o/
  Tracker.autorun ->
    PlaylistTracks.find().observeChanges
      changed: (id, fields) ->
        # Update now playing
        Meteor.call "nowPlaying", (error, track) ->
          Session.set "now_playing", track

# Routes
Router.map () ->
  this.route 'home', 
    path: '/'
      