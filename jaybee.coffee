# Collections
#
@PlaylistTracks = new Meteor.Collection("playlist_tracks")
@PlayedTracks = new Meteor.Collection("played_tracks")

# Functions
#
play = (id) ->
  track = PlaylistTracks.findOne id

  # Play it
  SC.stream "/tracks/#{track.track_id}", (sound, error) ->
    # Stop anything thats playing
    soundManager.stopAll()

    # Start playing the track
    sound.play
      onfinish: playNext
      whileplaying: ->
        elapsed id, @position
      onload: ->
        if @readyState == 2
          console.warn("There was a problem with the track.", @)
          playNext()

playNext = ->
  # Add to history
  addToHistory()

  # Clear the currently playing Session data
  clearPlaying()

  track = nextTrack()

  if track
    markAsNowPlaying track
  else
    console.log "Add a track to the playlist"

elapsed = (id, position) ->
  track = PlaylistTracks.findOne id

  if position > track.position
    PlaylistTracks.update track._id,
      $set:
        position: position

  elapsed_time = track_length position
  Session.set "local_elapsed_time", elapsed_time

clearPlaying = ->
  # Mark track as not playing
  track = nowPlaying()
  if track
    PlaylistTracks.remove(track._id)
  # console.log("Now playing (should be null): ", nowPlaying())

addToHistory = ->
  track = nowPlaying()
  if track
    PlayedTracks.insert
      track_id: track.track_id
      added_by: Meteor.user()
      upVotes: track.upVotes
      downVotes: track.downVotes
      created_at: timestamp()

upVote = ->
  track = nowPlaying()
  user_id = Meteor.user()._id
  PlaylistTracks.update track._id,
    $addToSet:
      upVotes: user_id
    $pull: 
      downVotes: user_id

downVote = ->
  track = nowPlaying()
  user_id = Meteor.user()._id
  PlaylistTracks.update track._id,
    $addToSet:
      downVotes: user_id
    $pull: 
      upVotes: user_id

nextTrack = ->
  # PlaylistTracks.findOne({now_playing: false}, {sort: [["created_at", "asc"]]})
  PlaylistTracks.findOne {now_playing: false}, 
    sort: [["created_at", "asc"]]

nowPlaying = ->
  # PlaylistTracks.findOne({now_playing: true}, {sort: [["created_at", "asc"]]})
  PlaylistTracks.findOne {now_playing: true},
    sort: [["created_at", "asc"]]

markAsNowPlaying = (track) ->
  # PlaylistTracks.update(track._id, {$set: {now_playing: true}})
  PlaylistTracks.update track._id,
    $set:
      now_playing: true

addToPlaylist = (track_id) ->
  SC.get "/tracks/#{track_id}", (track, error) ->
    if error
      Meteor.Error(404, error.message)
    else
      PlaylistTracks.insert
        track_id: track.id
        title:    track.title
        username: if track.user then track.user.username else "Unknown"
        duration: track.duration
        artwork_url: track.artwork_url
        permalink_url: track.permalink_url
        position: 0
        now_playing: false
        added_by: Meteor.user()
        upVotes: []
        downVotes: []
        created_at: timestamp()

removeFromPlaylist = (track_id) ->
  PlaylistTracks.remove track_id

favourite = (track_id) ->
  SC.put "/me/favorites/#{track_id}", (response) ->
    console.log response
    favourites = Session.get 'sc.favorites'
    newFavs = arrayUnique(favourites.concat([parseInt(track_id)]))
    Session.set 'sc.favorites', newFavs

unFavourite = (track_id) ->
  SC.delete "/me/favorites/#{track_id}", (response) ->
    favourites = Session.get 'sc.favorites'
    newFavs = arrayUnique(_.without(favourites, parseInt(track_id)))
    Session.set 'sc.favorites', newFavs

getFavorites = (offset = 0, limit = 200) ->
  offset = offset
  limit = limit
  favorites = Session.get 'sc.favorites'

  unless favorites
    Session.set 'sc.favorites', null
  
  SC.get "/me/favorites", {offset: offset, limit: limit}, (response, error) ->
    # Error?
    if error
      return

    # array of id's
    # [1,2,3,4] etc
    favorites = Session.get 'sc.favorites'
    favorites = if favorites == null then [] else favorites
    response.forEach (track) ->
      favorites.push track.id

    Session.set 'sc.favorites', arrayUnique(favorites)

    if response.length > 0
      offset = offset + limit
      getFavorites offset

arrayUnique = (array) ->
  a = array.concat()
  i = 0

  while i < a.length
    j = i + 1

    while j < a.length
      a.splice j--, 1  if a[i] is a[j]
      ++j
    ++i
  a

inFavorites = (track_id) ->
  favorites = Session.get('sc.favorites')
  if favorites
    return _.find Session.get('sc.favorites'), (track) ->
      if track.id == track_id
        return track

accessToken = ->
  return Meteor.user().services.soundcloud.accessToken

search = (search_query) ->
  page_size = 20
  SC.get "/tracks", 
    q: search_query,
    filter: "streamable, public",
    limit: page_size, (tracks) ->
      Session.set("search_results", tracks)

clearSearch = ->
  Session.set("search_results", null)  

track_length = (duration) ->
  seconds = parseInt((duration/1000)%60)
  minutes = parseInt((duration/(1000*60))%60)
  hours   = parseInt((duration/(1000*60*60))%24)

  hours   = if hours < 10 then "0" + hours else hours
  minutes = if minutes < 10 then "0" + minutes else minutes
  seconds = if seconds < 10 then "0" + seconds else seconds
  
  duration_string = ""
  duration_string += "#{hours}:" unless hours == "00"
  duration_string += "#{minutes}:#{seconds}"

  return duration_string

timestamp = ->
  new Date()

# Client
#
if Meteor.isClient
  accessTokenDep = new Deps.Dependency

  Meteor.subscribe 'SC.OAuth', ->
    if Meteor.user()
      # Set Access Token
      accessToken = Meteor.user().services.soundcloud.accessToken
      if accessToken
        accessTokenDep.changed()
        SC.accessToken accessToken

        # Get and set favorites
        getFavorites()

  Meteor.autosubscribe () ->
    PlaylistTracks.find().observeChanges
      changed: (id, fields) ->
        if fields.now_playing and fields.now_playing == true
          play id

  # Search
  Template.search.events 
    "keyup input.search": (event) ->
      query = event.currentTarget.value
      if query then search query else clearSearch()
      return

  # Search Results
  Template.searchResults.events 
    "click a.add": (event) ->
      event.preventDefault()
      addToPlaylist event.currentTarget.dataset.trackId
      return

  Template.searchResults.results = ->
    return Session.get("search_results")

  Template.searchResults.length = (duration) ->
    return track_length(duration)

  # Playlist
  Template.playlist.events 
    "click a.remove": (event) ->
      event.preventDefault()
      removeFromPlaylist event.currentTarget.dataset.trackId
      return

    "click a.favorite": (event) ->
      event.preventDefault()
      track_id = event.currentTarget.dataset.trackId
      favourite track_id
      return

    "click a.favorited": (event) ->
      event.preventDefault()
      track_id = event.currentTarget.dataset.trackId
      unFavourite track_id
      return

  Template.playlist.tracks = ->
    return PlaylistTracks.find {now_playing: false}, 
      sort: [["created_at", "asc"]]

  Template.playlist.length = (duration) ->
    return track_length(duration)

  Template.playlist.allowedToRemove = ->
    return @added_by._id == Meteor.user()._id

  Template.playlist.avatar_url = ->
    return @added_by.services.soundcloud.avatar_url

  Template.playlist.favourited = ->
    accessTokenDep.depend()

    favorites = Session.get 'sc.favorites'
    track = $.inArray @track_id, favorites

    return if track > -1 then "favorited" else "favorite"

  # Controls
  Template.controls.events 
    "click [data-control=play]": (event) ->
      event.preventDefault()

      track = nowPlaying()
      if track
        play track._id
      else
        playNext()
      return

    "click [data-control=next]": (event) ->
      event.preventDefault()
      playNext()
      return

    # Now Playing
    Template.now_playing.events
      "click a.favorite": (event) ->
        event.preventDefault()
        track_id = event.currentTarget.dataset.trackId
        favourite track_id
        return

      "click a.favorited": (event) ->
        event.preventDefault()
        track_id = event.currentTarget.dataset.trackId
        unFavourite track_id
        return

      "click [data-control=upvote]": (event) ->
        event.preventDefault()
        upVote()
        return

      "click [data-control=downvote]": (event) ->
        event.preventDefault()
        downVote()
        return

    Template.now_playing.now_playing = ->
      return nowPlaying()

    Template.now_playing.length = ->
      return track_length @duration

    Template.now_playing.elapsed = ->
      return Session.get "local_elapsed_time"

    Template.now_playing.avatar_url = ->
      return @added_by.services.soundcloud.avatar_url

    Template.now_playing.favourited = ->
      accessTokenDep.depend()

      favorites = Session.get 'sc.favorites'
      track = $.inArray @track_id, favorites

      return if track > -1 then "favorited" else "favorite"

    Template.now_playing.total_upVotes = ->
      return @upVotes.length

    Template.now_playing.total_downVotes = ->
      return @downVotes.length

    # Listeners
    Template.listeners.listeners = ->
      return Meteor.users.find({ "profile.online": true }).fetch()

# Server
#
if Meteor.isServer
  Meteor.startup ->

  Meteor.publish 'SC.OAuth', () ->
    return Meteor.users.find Meteor.userId, 
      fields: 
        'services.soundcloud': 1